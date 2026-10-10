-- A return records goods; the existing independent approval and cash flow records money.
ALTER TABLE payment_refunds ADD COLUMN store_return_id uuid,
 ADD CONSTRAINT payment_refund_store_return_fk FOREIGN KEY(store_return_id,organization_id,branch_id)
  REFERENCES store_returns(id,organization_id,branch_id);
CREATE INDEX payment_refund_store_return_idx ON payment_refunds(store_return_id) WHERE store_return_id IS NOT NULL;
CREATE FUNCTION validate_store_return_refund() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE r store_returns%ROWTYPE; e payment_events%ROWTYPE; a payment_attempts%ROWTYPE; l sale_lines%ROWTYPE; refunded numeric;
BEGIN
 IF NEW.store_return_id IS NULL THEN RETURN NEW; END IF;
 IF NEW.payment_event_id IS NULL THEN RAISE EXCEPTION 'A store return refund needs an original payment' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-return-refund:'||NEW.store_return_id,0));
 SELECT * INTO r FROM store_returns WHERE id=NEW.store_return_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT * INTO l FROM sale_lines WHERE id=r.sale_line_id;
 SELECT * INTO e FROM payment_events WHERE id=NEW.payment_event_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id AND outcome='confirmed';
 SELECT * INTO a FROM payment_attempts WHERE id=e.attempt_id;
 SELECT coalesce(sum(amount_usd),0) INTO refunded FROM payment_refunds WHERE store_return_id=r.id;
 IF r.id IS NULL OR l.id IS NULL OR e.id IS NULL OR a.sale_id<>l.sale_id
  OR NEW.amount_usd>r.amount_eligible_usd-refunded THEN
  RAISE EXCEPTION 'Refund exceeds return or references a different sale' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER store_return_refund_guard BEFORE INSERT ON payment_refunds FOR EACH ROW EXECUTE FUNCTION validate_store_return_refund();
REVOKE ALL ON FUNCTION validate_store_return_refund() FROM PUBLIC,anon,authenticated,service_role;
