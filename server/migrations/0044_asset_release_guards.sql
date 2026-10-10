CREATE FUNCTION guard_asset_block_resolution() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF OLD.resolved_at IS NOT NULL AND (NEW.resolved_at IS DISTINCT FROM OLD.resolved_at OR NEW.resolved_by IS DISTINCT FROM OLD.resolved_by) THEN
  RAISE EXCEPTION 'Resolved block cannot be rewritten' USING ERRCODE='23514'; END IF;
 IF OLD.resolved_at IS NULL AND NEW.resolved_at IS NOT NULL AND OLD.block_type IN('safety','technical') THEN
  IF NOT EXISTS(SELECT 1 FROM maintenance_work_orders w WHERE w.target_block_id=OLD.id AND w.branch_id=OLD.branch_id
    AND w.organization_id=OLD.organization_id AND w.status='verified' AND w.verified_by IS DISTINCT FROM NEW.resolved_by) THEN
   RAISE EXCEPTION 'Safety or technical block needs a verified work order' USING ERRCODE='23514'; END IF;
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER asset_block_resolution_guard BEFORE UPDATE ON asset_blocks FOR EACH ROW EXECUTE FUNCTION guard_asset_block_resolution();
CREATE FUNCTION guard_asset_activation() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE state_value text; kind text;
BEGIN
 kind:=TG_ARGV[0];
 IF kind='tank' THEN state_value:=NEW.status; ELSE state_value:=NEW.physical_status; END IF;
 IF state_value='active' AND EXISTS(SELECT 1 FROM asset_blocks b WHERE b.asset_type=kind AND b.asset_id=NEW.id
   AND b.branch_id=NEW.branch_id AND b.organization_id=NEW.organization_id AND b.resolved_at IS NULL) THEN
  RAISE EXCEPTION 'Cannot activate asset with unresolved blocks' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER tank_activation_guard BEFORE UPDATE OF status ON tanks FOR EACH ROW EXECUTE FUNCTION guard_asset_activation('tank');
CREATE TRIGGER dispenser_activation_guard BEFORE UPDATE OF physical_status ON dispensers FOR EACH ROW EXECUTE FUNCTION guard_asset_activation('dispenser');
CREATE TRIGGER nozzle_activation_guard BEFORE UPDATE OF physical_status ON nozzles FOR EACH ROW EXECUTE FUNCTION guard_asset_activation('nozzle');
REVOKE ALL ON FUNCTION guard_asset_block_resolution(),guard_asset_activation() FROM PUBLIC,anon,authenticated,service_role;
