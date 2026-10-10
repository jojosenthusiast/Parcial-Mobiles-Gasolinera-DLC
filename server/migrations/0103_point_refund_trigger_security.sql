BEGIN;

-- Refund trigger validators need their constrained reads under the table owner;
-- the API role remains unable to query ledgers/payment rows directly.
CREATE OR REPLACE FUNCTION validate_point_refund_request() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p customer_point_payments%ROWTYPE; occupied bigint;
BEGIN
 SELECT * INTO p FROM customer_point_payments WHERE id=NEW.payment_id FOR UPDATE;
 IF p.id IS NULL OR p.organization_id<>NEW.organization_id OR p.branch_id<>NEW.branch_id
 OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.requested_by AND organization_id=p.organization_id AND status='active') THEN
  RAISE EXCEPTION 'Point refund request scope mismatch' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(r.points),0) INTO occupied FROM customer_point_refund_requests r LEFT JOIN customer_point_refund_decisions d ON d.request_id=r.id
  WHERE r.payment_id=p.id AND (d.id IS NULL OR d.decision='approved');
 IF NEW.points>p.points-occupied THEN RAISE EXCEPTION 'Point refund exceeds unreserved points' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION validate_point_refund_request() FROM PUBLIC;
REVOKE ALL ON FUNCTION validate_point_refund_request() FROM anon, authenticated, service_role, dlc_api_runtime;

CREATE OR REPLACE FUNCTION validate_point_refund_decision() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r customer_point_refund_requests%ROWTYPE; p customer_point_payments%ROWTYPE; returned bigint; paid_back numeric;
BEGIN
 SELECT * INTO r FROM customer_point_refund_requests WHERE id=NEW.request_id FOR UPDATE;
 SELECT * INTO p FROM customer_point_payments WHERE id=r.payment_id FOR UPDATE;
 IF r.id IS NULL OR r.organization_id<>NEW.organization_id OR r.branch_id<>NEW.branch_id OR r.requested_by=NEW.decided_by
 OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.decided_by AND organization_id=r.organization_id AND status='active') THEN
  RAISE EXCEPTION 'Independent point refund decision required' USING ERRCODE='23514'; END IF;
 NEW.amount_usd:=0;
 IF NEW.decision='approved' THEN
  SELECT coalesce(sum(x.points),0),coalesce(sum(d.amount_usd),0) INTO returned,paid_back
   FROM customer_point_refund_requests x JOIN customer_point_refund_decisions d ON d.request_id=x.id
   WHERE x.payment_id=p.id AND d.decision='approved';
  IF returned+r.points>p.points THEN RAISE EXCEPTION 'Point refund exceeds original tender' USING ERRCODE='23514'; END IF;
  -- Cumulative rounding ensures the final refund returns the exact original cents.
  NEW.amount_usd:=floor(p.amount_usd*(returned+r.points)::numeric/p.points*100)/100-paid_back;
 END IF;
 RETURN NEW;
END; $$;
REVOKE ALL ON FUNCTION validate_point_refund_decision() FROM PUBLIC;
REVOKE ALL ON FUNCTION validate_point_refund_decision() FROM anon, authenticated, service_role, dlc_api_runtime;

COMMIT;
