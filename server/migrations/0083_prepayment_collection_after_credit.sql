-- Commercial-credit changes replaced the sale collection view and dropped
-- captured pre-dispatch advances from both reconciliation and payment limits.
CREATE OR REPLACE FUNCTION validate_payment_attempt() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE total numeric; occupied numeric; captured_allocated numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
 IF EXISTS(SELECT 1 FROM commercial_credit_charges WHERE sale_id=NEW.sale_id) THEN
  RAISE EXCEPTION 'Collect commercial credit through account statement' USING ERRCODE='23514';
 END IF;
 SELECT total_usd INTO total FROM sales
  WHERE id=NEW.sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT coalesce(sum(a.amount_usd),0) INTO occupied FROM payment_attempts a
  WHERE a.sale_id=NEW.sale_id
   AND NOT EXISTS(SELECT 1 FROM payment_events e WHERE e.attempt_id=a.id AND e.outcome='declined');
 SELECT coalesce(sum(al.amount_usd),0) INTO captured_allocated
  FROM prepayment_allocations al JOIN prepayment_advances adv ON adv.id=al.advance_id
  WHERE al.sale_id=NEW.sale_id AND adv.tender_kind='captured'
   AND prepayment_current_outcome(adv.id)='confirmed';
 IF total IS NULL OR NEW.amount_usd>total-occupied-captured_allocated THEN
  RAISE EXCEPTION 'Payment exceeds unreserved sale balance including captured advances' USING ERRCODE='23514';
 END IF;
 PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.created_by,NEW.organization_id,NEW.branch_id);
 RETURN NEW;
END; $$;

CREATE OR REPLACE VIEW sale_collection_balances WITH(security_invoker=true) AS
 SELECT s.id,s.organization_id,s.branch_id,
  CASE WHEN coalesce(p.collected,0)>=s.total_usd OR cc.id IS NOT NULL AND st.outstanding_usd=0 THEN 'paid'
   WHEN cc.id IS NOT NULL THEN 'on_credit' ELSE 'pending_collection' END AS collection_status,
  coalesce(p.collected,0) AS collected_usd,coalesce(p.reserved,0) AS reserved_usd,
  greatest(s.total_usd-coalesce(p.collected,0)-coalesce(cc.amount_usd,0),0) AS outstanding_usd,
  coalesce(r.refunded,0) AS refunded_usd,
  CASE WHEN coalesce(r.refunded,0)=0 THEN 'none' WHEN r.refunded>=p.collected THEN 'refunded' ELSE 'partial' END AS refund_status
 FROM sales s LEFT JOIN LATERAL(
  SELECT coalesce(sum(a.amount_usd) FILTER(WHERE e.outcome='confirmed'),0)+coalesce((
    SELECT sum(al.amount_usd) FROM prepayment_allocations al
     JOIN prepayment_advances adv ON adv.id=al.advance_id
    WHERE al.sale_id=s.id AND adv.tender_kind='captured'
     AND prepayment_current_outcome(adv.id)='confirmed'
  ),0) AS collected,
   sum(a.amount_usd) FILTER(WHERE e.outcome IS NULL OR e.outcome='unknown') AS reserved
  FROM payment_attempts a LEFT JOIN LATERAL(
   SELECT outcome FROM payment_events WHERE attempt_id=a.id
    ORDER BY (outcome<>'unknown') DESC,created_at DESC,id DESC LIMIT 1
  ) e ON true
  WHERE a.sale_id=s.id AND a.mode='manual'
 ) p ON true LEFT JOIN LATERAL(
  SELECT sum(rr.amount_usd) AS refunded FROM payment_refunds rr
   JOIN payment_events e ON e.id=rr.payment_event_id
   JOIN payment_attempts a ON a.id=e.attempt_id
  WHERE a.sale_id=s.id AND a.mode='manual'
 ) r ON true LEFT JOIN commercial_credit_charges cc ON cc.sale_id=s.id
 LEFT JOIN commercial_account_statement st ON st.id=cc.id;

REVOKE ALL ON FUNCTION validate_payment_attempt() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION validate_payment_attempt() TO dlc_api_runtime;
REVOKE ALL ON sale_collection_balances FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON sale_collection_balances TO dlc_api_runtime;
