-- Recoveries do not rewrite the original damage or the inventory ledger.
CREATE TABLE incident_recovery_claims (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 incident_id uuid NOT NULL,counterparty_type text NOT NULL CHECK(counterparty_type IN('third_party','insurer')),
 counterparty_name text NOT NULL CHECK(length(btrim(counterparty_name)) BETWEEN 2 AND 160),
 reference text NOT NULL CHECK(length(btrim(reference)) BETWEEN 3 AND 120),
 claimed_usd numeric(18,2) NOT NULL CHECK(claimed_usd>0),
 filed_by uuid NOT NULL,filed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(incident_id,organization_id,branch_id) REFERENCES incidents(id,organization_id,branch_id),
 FOREIGN KEY(filed_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,reference),UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE incident_recovery_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 claim_id uuid NOT NULL,amount_usd numeric(18,2) NOT NULL CHECK(amount_usd>0),
 method text NOT NULL CHECK(method IN('cash','bank_transfer','other')),
 evidence_reference text NOT NULL CHECK(length(btrim(evidence_reference)) BETWEEN 3 AND 200),
 command_id uuid NOT NULL,received_by uuid NOT NULL,received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(claim_id,organization_id,branch_id) REFERENCES incident_recovery_claims(id,organization_id,branch_id),
 FOREIGN KEY(received_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id),UNIQUE(organization_id,evidence_reference)
);
CREATE FUNCTION guard_recovery_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE cap numeric; paid numeric;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('recovery:'||NEW.claim_id::text,0));
 SELECT claimed_usd INTO cap FROM incident_recovery_claims WHERE id=NEW.claim_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT COALESCE(sum(amount_usd),0) INTO paid FROM incident_recovery_receipts WHERE claim_id=NEW.claim_id;
 IF cap IS NULL OR NEW.amount_usd+paid>cap THEN
  RAISE EXCEPTION 'Recovery exceeds claim or crosses branch' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER recovery_receipt_limit BEFORE INSERT ON incident_recovery_receipts
 FOR EACH ROW EXECUTE FUNCTION guard_recovery_receipt();
CREATE TRIGGER recovery_claim_immutable BEFORE UPDATE OR DELETE ON incident_recovery_claims
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE TRIGGER recovery_receipt_immutable BEFORE UPDATE OR DELETE ON incident_recovery_receipts
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE VIEW incident_recovery_balances WITH(security_invoker=true) AS
 SELECT c.id AS claim_id,c.organization_id,c.branch_id,c.incident_id,c.claimed_usd,
  COALESCE(sum(r.amount_usd),0)::numeric(18,2) AS recovered_usd,
  (c.claimed_usd-COALESCE(sum(r.amount_usd),0))::numeric(18,2) AS outstanding_usd
 FROM incident_recovery_claims c LEFT JOIN incident_recovery_receipts r ON r.claim_id=c.id GROUP BY c.id;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['incident_recovery_claims','incident_recovery_receipts'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
 END LOOP;
END $$;
REVOKE ALL ON incident_recovery_balances FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON incident_recovery_balances TO dlc_api_runtime;
REVOKE ALL ON FUNCTION guard_recovery_receipt() FROM PUBLIC,anon,authenticated,service_role;
