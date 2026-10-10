BEGIN;

-- A zero rate keeps point tender disabled. Only a newly approved policy can
-- define the conversion used by a future, audited point-payment flow.
ALTER TABLE customer_loyalty_programs
  ADD COLUMN redemption_usd_per_point numeric(12,6) NOT NULL DEFAULT 0,
  ADD CONSTRAINT customer_loyalty_redemption_rate_check
    CHECK (redemption_usd_per_point >= 0 AND redemption_usd_per_point <= 1000);

CREATE FUNCTION protect_customer_loyalty_redemption_rate() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF OLD.redemption_usd_per_point IS DISTINCT FROM NEW.redemption_usd_per_point THEN
    RAISE EXCEPTION 'Loyalty redemption rate is immutable; create a new policy version' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER customer_loyalty_redemption_rate_immutable
  BEFORE UPDATE ON customer_loyalty_programs
  FOR EACH ROW EXECUTE FUNCTION protect_customer_loyalty_redemption_rate();
REVOKE ALL ON FUNCTION protect_customer_loyalty_redemption_rate() FROM PUBLIC,anon,authenticated,service_role;

COMMIT;
