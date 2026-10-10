BEGIN;

-- Reverse previously earned points proportionally when a confirmed money tender
-- is refunded. The refund row remains the money authority; this ledger entry only
-- corrects points earned from that sale and never moves cash or inventory.
CREATE FUNCTION reverse_points_for_sale_refund() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_sale_id uuid; v_org_id uuid; v_branch_id uuid; v_customer_id uuid; v_program_id uuid;
  earned bigint; eligible numeric; refunded numeric; reversed bigint; target bigint; delta bigint;
BEGIN
  IF NEW.payment_event_id IS NULL THEN RETURN NEW; END IF;
  SELECT a.sale_id,a.organization_id,a.branch_id INTO v_sale_id,v_org_id,v_branch_id
    FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id
    WHERE e.id=NEW.payment_event_id AND e.organization_id=NEW.organization_id
      AND e.branch_id=NEW.branch_id AND e.outcome='confirmed' AND a.mode='manual'
      AND a.method IN('cash','card');
  IF v_sale_id IS NULL THEN RETURN NEW; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||v_sale_id::text,0));
  SELECT l.customer_id,pl.program_id,pl.points_delta INTO v_customer_id,v_program_id,earned
    FROM customer_sale_links l JOIN customer_points_ledger pl
      ON pl.organization_id=l.organization_id AND pl.customer_id=l.customer_id
     AND pl.source_type='sale' AND pl.source_id=l.sale_id AND pl.event_type='earn'
    WHERE l.sale_id=v_sale_id AND l.organization_id=v_org_id AND l.branch_id=v_branch_id;
  IF v_customer_id IS NULL OR earned IS NULL OR earned<=0 THEN RETURN NEW; END IF;
  SELECT coalesce(sum(a.amount_usd),0)+coalesce((SELECT sum(al.amount_usd)
    FROM prepayment_allocations al JOIN prepayment_advances adv ON adv.id=al.advance_id
    WHERE al.sale_id=v_sale_id AND adv.tender_kind='captured'
      AND prepayment_current_outcome(adv.id)='confirmed'),0)
    INTO eligible FROM payment_events e JOIN payment_attempts a ON a.id=e.attempt_id
    WHERE a.sale_id=v_sale_id AND a.organization_id=v_org_id AND a.branch_id=v_branch_id
      AND a.mode='manual' AND a.method IN('cash','card') AND e.outcome='confirmed';
  IF eligible<=0 THEN RETURN NEW; END IF;
  SELECT coalesce(sum(r.amount_usd),0) INTO refunded
    FROM payment_refunds r JOIN payment_events e ON e.id=r.payment_event_id
    JOIN payment_attempts a ON a.id=e.attempt_id
    WHERE a.sale_id=v_sale_id AND a.organization_id=v_org_id AND a.branch_id=v_branch_id;
  SELECT coalesce(-sum(points_delta),0) INTO reversed FROM customer_points_ledger
    WHERE organization_id=v_org_id AND customer_id=v_customer_id AND source_type='sale_refund'
      AND event_type='reverse' AND source_id IN (
        SELECT r.id FROM payment_refunds r JOIN payment_events e ON e.id=r.payment_event_id
        JOIN payment_attempts a ON a.id=e.attempt_id WHERE a.sale_id=v_sale_id);
  target:=floor(earned::numeric*least(refunded,eligible)/eligible)::bigint;
  delta:=greatest(target-reversed,0);
  IF delta>0 THEN
    INSERT INTO customer_points_ledger(organization_id,customer_id,program_id,event_type,points_delta,
      source_type,source_id,command_id,reason,created_by)
    VALUES(v_org_id,v_customer_id,v_program_id,'reverse',-delta,'sale_refund',NEW.id,NEW.id,
      'Reverso proporcional de puntos por reembolso monetario aprobado',NEW.created_by)
    ON CONFLICT(organization_id,source_type,source_id,event_type) DO NOTHING;
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER customer_points_reverse_on_payment_refund
  AFTER INSERT ON payment_refunds FOR EACH ROW EXECUTE FUNCTION reverse_points_for_sale_refund();
REVOKE ALL ON FUNCTION reverse_points_for_sale_refund() FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
