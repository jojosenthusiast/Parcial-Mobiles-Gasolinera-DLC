BEGIN;
CREATE TABLE contamination_incoming_loss_approvals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), contamination_id uuid NOT NULL UNIQUE REFERENCES contaminated_deliveries(id),
 organization_id uuid NOT NULL, branch_id uuid NOT NULL, command_id uuid NOT NULL, approved_by uuid NOT NULL REFERENCES users(id),
 amount_usd numeric(24,8) NOT NULL CHECK(amount_usd>=0), reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 8 AND 500),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(organization_id,command_id)
);
CREATE TABLE contamination_disposals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),contamination_id uuid NOT NULL UNIQUE REFERENCES contaminated_deliveries(id),
 organization_id uuid NOT NULL,branch_id uuid NOT NULL,command_id uuid NOT NULL,verified_by uuid NOT NULL REFERENCES users(id),
 measured_l numeric(24,9) NOT NULL CHECK(measured_l>0),evidence_reference text NOT NULL CHECK(length(btrim(evidence_reference)) BETWEEN 3 AND 120),
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 12 AND 1000),created_at timestamptz NOT NULL DEFAULT clock_timestamp(),UNIQUE(organization_id,command_id)
);
CREATE FUNCTION validate_contamination_scope() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM purchase_order_lines l JOIN purchase_orders o ON o.id=l.purchase_order_id
   WHERE l.id=NEW.purchase_order_line_id AND o.id=NEW.purchase_order_id AND o.organization_id=NEW.organization_id AND o.branch_id=NEW.branch_id
    AND l.fuel_product_id=NEW.incoming_product_id AND l.unit=NEW.unit)
 OR NOT EXISTS(SELECT 1 FROM tanks t WHERE t.id=NEW.tank_id AND t.organization_id=NEW.organization_id AND t.branch_id=NEW.branch_id AND t.fuel_product_id=NEW.original_product_id)
 OR NOT EXISTS(SELECT 1 FROM incidents i WHERE i.id=NEW.incident_id AND i.organization_id=NEW.organization_id AND i.branch_id=NEW.branch_id AND i.asset_id=NEW.tank_id AND i.category='wrong_tank_delivery')
 OR NOT EXISTS(SELECT 1 FROM users u WHERE u.id=NEW.reported_by AND u.organization_id=NEW.organization_id AND u.status='active') THEN
  RAISE EXCEPTION 'Contaminated delivery scope mismatch' USING ERRCODE='23514'; END IF;
 IF NEW.incoming_quantity_l IS DISTINCT FROM round(NEW.actual_quantity*CASE WHEN NEW.unit='us_gallon' THEN 3.785411784 ELSE 1 END,9) THEN
  RAISE EXCEPTION 'Contaminated delivery unit mismatch' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER contamination_scope_guard BEFORE INSERT ON contaminated_deliveries FOR EACH ROW EXECUTE FUNCTION validate_contamination_scope();
CREATE FUNCTION validate_contamination_resolution() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE d contaminated_deliveries%ROWTYPE;
BEGIN
 SELECT * INTO d FROM contaminated_deliveries WHERE id=NEW.contamination_id FOR UPDATE;
 IF d.id IS NULL OR d.organization_id<>NEW.organization_id OR d.branch_id<>NEW.branch_id THEN RAISE EXCEPTION 'Contamination scope mismatch' USING ERRCODE='23514'; END IF;
 IF TG_TABLE_NAME='contamination_incoming_loss_approvals' THEN
  IF NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.approved_by AND organization_id=d.organization_id AND status='active') THEN RAISE EXCEPTION 'Inactive loss approver' USING ERRCODE='23514'; END IF;
  IF NEW.approved_by=d.reported_by OR NEW.amount_usd<>d.incoming_cost_usd THEN RAISE EXCEPTION 'Independent incoming loss approval required' USING ERRCODE='23514'; END IF;
 ELSE
  IF NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.verified_by AND organization_id=d.organization_id AND status='active') THEN RAISE EXCEPTION 'Inactive disposal verifier' USING ERRCODE='23514'; END IF;
  IF NEW.verified_by=d.reported_by OR NOT EXISTS(SELECT 1 FROM contamination_incoming_loss_approvals WHERE contamination_id=d.id) OR
    (d.prior_quantity_l>0 AND NOT EXISTS(SELECT 1 FROM incident_impact_assessments a JOIN incident_loss_approvals l ON l.assessment_id=a.id
      WHERE a.incident_id=d.incident_id AND a.tank_id=d.tank_id AND l.movement_id IS NOT NULL)) THEN
   RAISE EXCEPTION 'Disposal requires independent verification and both approved losses' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE FUNCTION guard_contamination_release() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF OLD.resolved_at IS NULL AND NEW.resolved_at IS NOT NULL AND EXISTS(SELECT 1 FROM contaminated_deliveries d WHERE d.incident_id=OLD.incident_id
   AND NOT EXISTS(SELECT 1 FROM contamination_disposals x WHERE x.contamination_id=d.id)) THEN
  RAISE EXCEPTION 'Contaminated tank requires verified physical disposal' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER contamination_release_guard BEFORE UPDATE ON asset_blocks FOR EACH ROW EXECUTE FUNCTION guard_contamination_release();
CREATE FUNCTION guard_contamination_incident_closure() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.status='closed' AND OLD.status IS DISTINCT FROM NEW.status AND EXISTS(
  SELECT 1 FROM contaminated_deliveries d WHERE d.incident_id=NEW.id AND (
   NOT EXISTS(SELECT 1 FROM contamination_disposals x WHERE x.contamination_id=d.id) OR EXISTS(
    SELECT 1 FROM asset_blocks b WHERE b.incident_id=d.incident_id AND b.resolved_at IS NULL))) THEN
  RAISE EXCEPTION 'Contamination closure requires verified disposal and safe release' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER contamination_incident_closure_guard BEFORE UPDATE ON incidents FOR EACH ROW EXECUTE FUNCTION guard_contamination_incident_closure();
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['contamination_incoming_loss_approvals','contamination_disposals'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
  EXECUTE format('CREATE TRIGGER resolution_guard BEFORE INSERT ON %I FOR EACH ROW EXECUTE FUNCTION validate_contamination_resolution()',t);
  EXECUTE format('CREATE TRIGGER immutable_guard BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',t);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION guard_contamination_incident_closure(),validate_contamination_scope(),validate_contamination_resolution(),guard_contamination_release() FROM PUBLIC,anon,authenticated,service_role;
COMMIT;
