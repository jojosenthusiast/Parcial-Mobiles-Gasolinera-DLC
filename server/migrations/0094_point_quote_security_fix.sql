BEGIN;
CREATE OR REPLACE FUNCTION protect_customer_point_payment_quote() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF OLD.id IS DISTINCT FROM NEW.id OR OLD.created_at IS DISTINCT FROM NEW.created_at OR OLD.organization_id IS DISTINCT FROM NEW.organization_id OR OLD.branch_id IS DISTINCT FROM NEW.branch_id
    OR OLD.sale_id IS DISTINCT FROM NEW.sale_id OR OLD.customer_id IS DISTINCT FROM NEW.customer_id
    OR OLD.cash_session_id IS DISTINCT FROM NEW.cash_session_id OR OLD.program_id IS DISTINCT FROM NEW.program_id
    OR OLD.points IS DISTINCT FROM NEW.points OR OLD.amount_usd IS DISTINCT FROM NEW.amount_usd
    OR OLD.redemption_usd_per_point IS DISTINCT FROM NEW.redemption_usd_per_point
    OR OLD.expires_at IS DISTINCT FROM NEW.expires_at OR OLD.command_id IS DISTINCT FROM NEW.command_id
    OR OLD.request_hash IS DISTINCT FROM NEW.request_hash OR OLD.requested_by IS DISTINCT FROM NEW.requested_by THEN
    RAISE EXCEPTION 'Point payment quote facts are immutable' USING ERRCODE='55000';
  END IF;
  IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
    OLD.status='pending' AND NEW.status IN('confirmed','declined','expired')
  ) THEN RAISE EXCEPTION 'Invalid point payment quote transition' USING ERRCODE='23514'; END IF;
  IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
      (NEW.status='expired' AND NEW.expires_at<=clock_timestamp() AND NEW.decision_command_id IS NULL
        AND NEW.decision_hash IS NULL AND NEW.decided_by_customer_id IS NULL)
      OR (NEW.status IN('confirmed','declined') AND NEW.decision_command_id IS NOT NULL AND NEW.decision_hash IS NOT NULL
        AND NEW.decided_by_customer_id IS NOT DISTINCT FROM OLD.customer_id)) THEN
    RAISE EXCEPTION 'Point quote decision must be idempotent and made by its customer' USING ERRCODE='23514';
  END IF;
  IF OLD.status = NEW.status AND (OLD.decision_command_id IS DISTINCT FROM NEW.decision_command_id
    OR OLD.decision_hash IS DISTINCT FROM NEW.decision_hash OR OLD.decided_by_customer_id IS DISTINCT FROM NEW.decided_by_customer_id
    OR OLD.confirmed_at IS DISTINCT FROM NEW.confirmed_at) THEN
    RAISE EXCEPTION 'Point quote decisions are immutable' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION award_points_for_paid_customer_sale() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE sale_row record; program_row customer_loyalty_programs%ROWTYPE; eligible numeric; points bigint; ledger_command uuid; actor uuid;
BEGIN
  IF TG_TABLE_NAME='payment_events' THEN
    IF NEW.outcome<>'confirmed' THEN RETURN NEW; END IF;
    SELECT s.id,s.organization_id,s.total_usd,l.customer_id,b.collection_status
      INTO sale_row FROM payment_attempts a JOIN sales s ON s.id=a.sale_id AND s.organization_id=a.organization_id AND s.branch_id=a.branch_id
      JOIN sale_collection_balances b ON b.id=s.id AND b.organization_id=s.organization_id AND b.branch_id=s.branch_id
      JOIN customer_sale_links l ON l.sale_id=s.id AND l.organization_id=s.organization_id AND l.branch_id=s.branch_id
      WHERE a.id=NEW.attempt_id AND a.organization_id=NEW.organization_id AND a.branch_id=NEW.branch_id;
  ELSE
    SELECT s.id,s.organization_id,s.total_usd,l.customer_id,b.collection_status
      INTO sale_row FROM sales s JOIN sale_collection_balances b ON b.id=s.id AND b.organization_id=s.organization_id AND b.branch_id=s.branch_id
      JOIN customer_sale_links l ON l.sale_id=s.id AND l.organization_id=s.organization_id AND l.branch_id=s.branch_id
      WHERE s.id=NEW.sale_id AND s.organization_id=NEW.organization_id AND s.branch_id=NEW.branch_id;
  END IF;
  IF sale_row.id IS NULL OR sale_row.collection_status<>'paid' THEN RETURN NEW; END IF;
  SELECT * INTO program_row FROM customer_loyalty_programs
   WHERE organization_id=sale_row.organization_id AND status='active' ORDER BY version DESC LIMIT 1;
  IF program_row.id IS NULL THEN RETURN NEW; END IF;
  SELECT coalesce(sum(a.amount_usd),0)+coalesce((SELECT sum(al.amount_usd)
    FROM prepayment_allocations al JOIN prepayment_advances adv ON adv.id=al.advance_id
    WHERE al.sale_id=sale_row.id AND adv.tender_kind='captured'
      AND prepayment_current_outcome(adv.id)='confirmed'),0) INTO eligible
    FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id
    WHERE a.sale_id=sale_row.id AND a.organization_id=sale_row.organization_id
      AND a.branch_id=sale_row.branch_id AND a.mode='manual' AND a.method IN('cash','card') AND e.outcome='confirmed';
  IF eligible<program_row.minimum_eligible_usd THEN RETURN NEW; END IF;
  points:=floor(eligible*program_row.points_per_eligible_usd)::bigint;
  IF points<=0 THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME='payment_events' THEN
    ledger_command:=NEW.command_id;
    actor:=NEW.created_by;
  ELSE
    ledger_command:=gen_random_uuid();
    actor:=NULL;
  END IF;
  INSERT INTO customer_points_ledger(organization_id,customer_id,program_id,event_type,points_delta,
    source_type,source_id,command_id,reason,expires_at,created_by)
  VALUES(sale_row.organization_id,sale_row.customer_id,program_row.id,'earn',points,'sale',sale_row.id,
    ledger_command,'Puntos por porción pagada en efectivo/tarjeta de una venta',
    CASE WHEN program_row.points_expire_after_days IS NULL THEN NULL ELSE now()+(program_row.points_expire_after_days::text||' days')::interval END,
    actor)
  ON CONFLICT(organization_id,source_type,source_id,event_type) DO NOTHING;
  RETURN NEW;
END; $$;
COMMIT;
