-- Recheck real time after lock waits; transaction now() may be stale.
ALTER TABLE fuel_tax_proposals ALTER COLUMN proposed_at SET DEFAULT clock_timestamp();
ALTER TABLE fuel_tax_versions ALTER COLUMN approved_at SET DEFAULT clock_timestamp();
CREATE FUNCTION stamp_fuel_tax_proposal_time() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 NEW.proposed_at:=clock_timestamp();
 IF NEW.effective_at<=NEW.proposed_at THEN RAISE EXCEPTION 'Tax proposal must have future effectiveness' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER fuel_tax_proposal_clock BEFORE INSERT ON fuel_tax_proposals FOR EACH ROW EXECUTE FUNCTION stamp_fuel_tax_proposal_time();
REVOKE ALL ON FUNCTION stamp_fuel_tax_proposal_time() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION validate_fuel_tax_version() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p fuel_tax_proposals%ROWTYPE;
BEGIN
 NEW.approved_at:=clock_timestamp();
 IF NEW.effective_at<=NEW.approved_at THEN RAISE EXCEPTION 'Tax policy expired while waiting for approval' USING ERRCODE='23514'; END IF;
 SELECT * INTO p FROM fuel_tax_proposals WHERE id=NEW.proposal_id;
 IF p.id IS NULL OR NEW.approved_by=p.proposed_by OR NEW.mode IS DISTINCT FROM p.mode OR NEW.rules IS DISTINCT FROM p.rules
   OR NEW.source_reference IS DISTINCT FROM p.source_reference OR NEW.effective_at IS DISTINCT FROM p.effective_at THEN
  RAISE EXCEPTION 'Tax approval must preserve proposal and use another approver' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
