-- A combined internal receipt groups one immutable fuel ticket and one
-- immutable POS ticket. Collection and tax facts remain on their source sales.
CREATE TABLE combined_internal_receipts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 organization_id uuid NOT NULL,
 branch_id uuid NOT NULL,
 fuel_sale_id uuid NOT NULL,
 pos_sale_id uuid NOT NULL,
 command_id uuid NOT NULL,
 request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 correlation_id uuid NOT NULL,
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(fuel_sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
 FOREIGN KEY(pos_sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(fuel_sale_id<>pos_sale_id),
 UNIQUE(organization_id,command_id),
 UNIQUE(fuel_sale_id),
 UNIQUE(pos_sale_id),
 UNIQUE(id,organization_id,branch_id)
);
CREATE INDEX combined_internal_receipt_branch_idx
 ON combined_internal_receipts(organization_id,branch_id,created_at DESC,id DESC);

CREATE FUNCTION validate_combined_internal_receipt() RETURNS trigger
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE fuel sales%ROWTYPE; pos sales%ROWTYPE; sale_id uuid;
BEGIN
 -- Match payment-attempt locking so grouping cannot race a first collection.
 FOR sale_id IN SELECT unnest(ARRAY[NEW.fuel_sale_id,NEW.pos_sale_id]) ORDER BY 1 LOOP
  PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||sale_id::text,0));
 END LOOP;
 SELECT * INTO fuel FROM sales WHERE id=NEW.fuel_sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 SELECT * INTO pos FROM sales WHERE id=NEW.pos_sale_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id;
 IF fuel.id IS NULL OR pos.id IS NULL OR fuel.authorization_id IS NULL OR pos.authorization_id IS NOT NULL THEN
  RAISE EXCEPTION 'Combined internal receipt requires one fuel and one POS sale in the same branch' USING ERRCODE='23514';
 END IF;
 IF EXISTS(SELECT 1 FROM sale_collection_balances WHERE id IN(NEW.fuel_sale_id,NEW.pos_sale_id) AND collection_status<>'pending_collection')
   OR EXISTS(SELECT 1 FROM payment_attempts WHERE sale_id IN(NEW.fuel_sale_id,NEW.pos_sale_id))
   OR EXISTS(SELECT 1 FROM prepayment_allocations WHERE sale_id=NEW.fuel_sale_id)
   OR EXISTS(SELECT 1 FROM prepayment_advances WHERE authorization_id=fuel.authorization_id)
   OR EXISTS(SELECT 1 FROM store_returns r JOIN sale_lines l ON l.id=r.sale_line_id WHERE l.sale_id=NEW.pos_sale_id) THEN
  RAISE EXCEPTION 'Sales with previous collection activity cannot be grouped' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER combined_internal_receipt_validate
 BEFORE INSERT ON combined_internal_receipts
 FOR EACH ROW EXECUTE FUNCTION validate_combined_internal_receipt();
CREATE TRIGGER combined_internal_receipt_immutable
 BEFORE UPDATE OR DELETE ON combined_internal_receipts
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION validate_combined_internal_receipt() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON TABLE combined_internal_receipts FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE combined_internal_receipts ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT ON combined_internal_receipts TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON combined_internal_receipts FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON combined_internal_receipts FOR INSERT TO dlc_api_runtime WITH CHECK(true);

-- Prevent attaching a later commercial-credit charge or advance to a source
-- ticket after it has already been presented in the combined document.
CREATE FUNCTION guard_credit_for_combined_receipt() RETURNS trigger
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM combined_internal_receipts WHERE organization_id=NEW.organization_id AND branch_id=NEW.branch_id
   AND (fuel_sale_id=NEW.sale_id OR pos_sale_id=NEW.sale_id)) THEN
  RAISE EXCEPTION 'A combined internal receipt cannot be converted to commercial credit' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER combined_receipt_credit_guard BEFORE INSERT ON commercial_credit_charges
 FOR EACH ROW EXECUTE FUNCTION guard_credit_for_combined_receipt();

CREATE FUNCTION guard_advance_for_combined_receipt() RETURNS trigger
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF EXISTS(SELECT 1 FROM sales s JOIN combined_internal_receipts c ON c.fuel_sale_id=s.id
   WHERE s.authorization_id=NEW.authorization_id AND s.organization_id=NEW.organization_id AND s.branch_id=NEW.branch_id) THEN
  RAISE EXCEPTION 'A combined internal receipt cannot receive a new prepayment' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER combined_receipt_advance_guard BEFORE INSERT ON prepayment_advances
 FOR EACH ROW EXECUTE FUNCTION guard_advance_for_combined_receipt();
REVOKE ALL ON FUNCTION guard_credit_for_combined_receipt(),guard_advance_for_combined_receipt() FROM PUBLIC,anon,authenticated,service_role;
