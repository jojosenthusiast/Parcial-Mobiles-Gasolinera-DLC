BEGIN;

-- Trigger validation must read locked sale facts under the restricted API role.
-- A fixed search_path and migration-owned function prevent object shadowing while
-- preserving the runtime role's lack of direct access to sales.
CREATE OR REPLACE FUNCTION validate_customer_point_payment() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q customer_point_payment_quotes%ROWTYPE; s sales%ROWTYPE; balance bigint; available numeric;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
  SELECT * INTO q FROM customer_point_payment_quotes WHERE id=NEW.quote_id
    AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id FOR UPDATE;
  SELECT * INTO s FROM sales WHERE id=NEW.sale_id AND organization_id=NEW.organization_id
    AND branch_id=NEW.branch_id FOR UPDATE;
  IF q.id IS NULL OR s.id IS NULL OR q.status<>'pending' OR q.expires_at<=clock_timestamp()
    OR q.sale_id<>NEW.sale_id OR q.customer_id<>NEW.customer_id OR q.program_id<>NEW.program_id
    OR q.points<>NEW.points OR q.amount_usd<>NEW.amount_usd
    OR q.redemption_usd_per_point<>NEW.redemption_usd_per_point THEN
    RAISE EXCEPTION 'Point payment quote is invalid, expired or already used' USING ERRCODE='23514';
  END IF;
  PERFORM 1 FROM customer_accounts WHERE id=NEW.customer_id AND organization_id=NEW.organization_id
    AND status='active' FOR UPDATE;
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM customer_sale_links WHERE sale_id=NEW.sale_id
      AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id AND customer_id=NEW.customer_id) THEN
    RAISE EXCEPTION 'An active linked customer is required' USING ERRCODE='23514';
  END IF;
  SELECT coalesce(sum(points_delta),0) INTO balance FROM customer_points_ledger
    WHERE organization_id=NEW.organization_id AND customer_id=NEW.customer_id;
  IF NEW.points>balance THEN RAISE EXCEPTION 'Insufficient available points' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS(SELECT 1 FROM customer_loyalty_programs WHERE id=NEW.program_id
      AND organization_id=NEW.organization_id AND status='active'
      AND redemption_usd_per_point=NEW.redemption_usd_per_point AND redemption_usd_per_point>0) THEN
    RAISE EXCEPTION 'The approved point redemption policy is no longer active' USING ERRCODE='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM commercial_credit_charges WHERE sale_id=NEW.sale_id) THEN
    RAISE EXCEPTION 'Points cannot be applied to a commercial credit sale' USING ERRCODE='23514';
  END IF;
  SELECT greatest(s.total_usd-coalesce(p.collected,0)-coalesce(p.reserved,0),0) INTO available
    FROM sales s LEFT JOIN LATERAL(
      SELECT coalesce(sum(a.amount_usd) FILTER(WHERE e.outcome='confirmed'),0)
        + coalesce((SELECT sum(al.amount_usd) FROM prepayment_allocations al
          JOIN prepayment_advances adv ON adv.id=al.advance_id
          WHERE al.sale_id=s.id AND adv.tender_kind='captured' AND prepayment_current_outcome(adv.id)='confirmed'),0)
        + coalesce((SELECT sum(cp.amount_usd) FROM customer_point_payments cp WHERE cp.sale_id=s.id),0) AS collected,
        coalesce(sum(a.amount_usd) FILTER(WHERE e.outcome IS NULL OR e.outcome='unknown'),0) AS reserved
      FROM payment_attempts a LEFT JOIN LATERAL(SELECT outcome FROM payment_events WHERE attempt_id=a.id
        ORDER BY (outcome<>'unknown') DESC,created_at DESC,id DESC LIMIT 1)e ON true
      WHERE a.sale_id=s.id AND a.mode='manual'
    )p ON true WHERE s.id=NEW.sale_id;
  IF available IS NULL OR NEW.amount_usd>available THEN
    RAISE EXCEPTION 'Point tender exceeds the sale balance' USING ERRCODE='23514';
  END IF;
  PERFORM 1 FROM cash_sessions cs WHERE cs.id=q.cash_session_id AND cs.organization_id=NEW.organization_id
    AND cs.branch_id=NEW.branch_id AND NOT EXISTS(SELECT 1 FROM cash_closures cc WHERE cc.session_id=cs.id)
    FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'The cashier session is already closed' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION validate_customer_point_payment() FROM PUBLIC;
REVOKE ALL ON FUNCTION validate_customer_point_payment() FROM anon, authenticated, service_role, dlc_api_runtime;

COMMIT;
