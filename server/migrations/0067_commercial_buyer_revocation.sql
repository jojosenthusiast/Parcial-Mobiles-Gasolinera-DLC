-- Buyer access can be revoked without deleting historical sale attribution.
CREATE TABLE commercial_buyer_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,customer_id uuid NOT NULL,buyer_id uuid NOT NULL,
 active boolean NOT NULL,reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 changed_by uuid NOT NULL,changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(customer_id,organization_id) REFERENCES commercial_customers(id,organization_id),
 FOREIGN KEY(buyer_id,customer_id) REFERENCES commercial_authorized_buyers(id,customer_id),
 FOREIGN KEY(changed_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id)
);
DROP TRIGGER credit_fact_immutable ON commercial_authorized_buyers;
CREATE FUNCTION apply_commercial_buyer_event() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE b commercial_authorized_buyers%ROWTYPE;
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('commercial-buyer:'||NEW.buyer_id,0));
 SELECT * INTO b FROM commercial_authorized_buyers WHERE id=NEW.buyer_id;
 IF b.id IS NULL OR b.customer_id<>NEW.customer_id OR b.organization_id<>NEW.organization_id
  OR b.active=NEW.active OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.changed_by AND organization_id=NEW.organization_id AND status='active')
 THEN RAISE EXCEPTION 'Buyer access transition invalid' USING ERRCODE='23514'; END IF;
 UPDATE commercial_authorized_buyers SET active=NEW.active WHERE id=b.id;
 RETURN NEW;
END $$;
CREATE TRIGGER buyer_event_apply BEFORE INSERT ON commercial_buyer_events
 FOR EACH ROW EXECUTE FUNCTION apply_commercial_buyer_event();
ALTER TABLE commercial_buyer_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON commercial_buyer_events FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON commercial_buyer_events TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON commercial_buyer_events FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON commercial_buyer_events FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE TRIGGER buyer_event_immutable BEFORE UPDATE OR DELETE ON commercial_buyer_events
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION apply_commercial_buyer_event() FROM PUBLIC,anon,authenticated,service_role;
