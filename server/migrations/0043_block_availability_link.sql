-- A block starts an observed outage when its asset has a maintenance profile.
CREATE FUNCTION track_new_asset_block() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE profile uuid; current_reason text; new_reason text;
BEGIN
 SELECT p.id INTO profile FROM maintenance_asset_profiles p WHERE p.organization_id=NEW.organization_id
  AND p.branch_id=NEW.branch_id AND p.asset_type=NEW.asset_type AND p.asset_id=NEW.asset_id;
 IF profile IS NULL THEN RETURN NEW; END IF;
 new_reason:=CASE WHEN NEW.block_type='inventory' THEN 'no_product'
   WHEN NEW.block_type='operational' THEN 'closed' ELSE 'technical_failure' END;
 SELECT i.reason INTO current_reason FROM asset_operating_intervals i WHERE i.asset_profile_id=profile AND i.ended_at IS NULL;
 IF current_reason IS DISTINCT FROM new_reason THEN
  PERFORM transition_asset_interval(NEW.organization_id,NEW.branch_id,profile,NEW.created_by,new_reason,clock_timestamp(),NULL);
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER asset_block_interval AFTER INSERT ON asset_blocks FOR EACH ROW EXECUTE FUNCTION track_new_asset_block();
REVOKE ALL ON FUNCTION track_new_asset_block() FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION release_maintenance_block(org uuid,branch uuid,target_order uuid,target_block uuid,actor uuid,release_reason text)
 RETURNS TABLE(block_id uuid,remaining_blocks integer,can_operate boolean)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE w maintenance_work_orders%ROWTYPE; asset maintenance_asset_profiles%ROWTYPE; block asset_blocks%ROWTYPE; remains integer;
BEGIN
 SELECT x.* INTO w FROM maintenance_work_orders x WHERE x.id=target_order AND x.organization_id=org AND x.branch_id=branch FOR UPDATE;
 SELECT x.* INTO asset FROM maintenance_asset_profiles x WHERE x.id=w.asset_profile_id;
 SELECT x.* INTO block FROM asset_blocks x WHERE x.id=target_block AND x.organization_id=org AND x.branch_id=branch FOR UPDATE;
 IF w.id IS NULL OR w.status<>'verified' OR asset.id IS NULL OR block.id IS NULL OR block.resolved_at IS NOT NULL OR
  block.asset_type<>asset.asset_type OR block.asset_id<>asset.asset_id OR w.target_block_id IS DISTINCT FROM target_block OR
  (w.incident_id IS NOT NULL AND block.incident_id IS DISTINCT FROM w.incident_id) OR
  (w.verified_by IS NULL OR w.verified_by=actor) THEN
  RAISE EXCEPTION 'Verified independent work order cannot release this block' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive release actor' USING ERRCODE='23514'; END IF;
 UPDATE asset_blocks SET resolved_by=actor,resolved_at=clock_timestamp(),resolution=release_reason WHERE id=target_block;
 SELECT count(*) INTO remains FROM asset_blocks b WHERE b.organization_id=org AND b.branch_id=branch AND
   b.asset_type=asset.asset_type AND b.asset_id=asset.asset_id AND b.resolved_at IS NULL;
 IF remains=0 THEN
  IF asset.asset_type='nozzle' THEN UPDATE nozzles SET physical_status='active',version=version+1 WHERE id=asset.asset_id AND physical_status IN('maintenance','offline');
  ELSIF asset.asset_type='dispenser' THEN UPDATE dispensers SET physical_status='active',version=version+1 WHERE id=asset.asset_id AND physical_status IN('maintenance','offline');
  ELSIF asset.asset_type='tank' THEN UPDATE tanks SET status='active',version=version+1 WHERE id=asset.asset_id AND status IN('maintenance','offline'); END IF;
  IF NOT EXISTS(SELECT 1 FROM asset_operating_intervals i WHERE i.asset_profile_id=asset.id AND i.ended_at IS NULL AND i.reason='available') THEN
   PERFORM transition_asset_interval(org,branch,asset.id,actor,'available',clock_timestamp(),target_order);
  END IF;
 END IF;
 RETURN QUERY SELECT target_block,remains,remains=0;
END; $$;

