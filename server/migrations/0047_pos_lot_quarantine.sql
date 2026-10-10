-- A lot can be quarantined without deleting its stock or rewriting its receipt.
CREATE TABLE pos_lot_condition_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,lot_id uuid NOT NULL,
 previous_condition text NOT NULL,new_condition text NOT NULL CHECK(new_condition IN('sellable','quarantine')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 actor_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(lot_id,organization_id,branch_id) REFERENCES pos_stock_lots(id,organization_id,branch_id),
 FOREIGN KEY(actor_id,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id)
);
ALTER TABLE pos_lot_condition_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pos_lot_condition_events FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON pos_lot_condition_events TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON pos_lot_condition_events FOR SELECT TO dlc_api_runtime USING(true);
CREATE TRIGGER pos_condition_event_immutable BEFORE UPDATE OR DELETE ON pos_lot_condition_events
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();

-- The runtime must use the guarded function; the former UPDATE grant was too broad.
REVOKE UPDATE ON pos_stock_lots FROM dlc_api_runtime;
DROP POLICY dlc_api_update ON pos_stock_lots;
CREATE FUNCTION set_pos_lot_condition(p_org uuid,p_branch uuid,p_actor uuid,p_lot uuid,
 p_condition text,p_reason text,p_command uuid,p_hash text,p_correlation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE l pos_stock_lots%ROWTYPE; existing pos_lot_condition_events%ROWTYPE; event_id uuid; local_date date;
BEGIN
 IF p_condition NOT IN('sellable','quarantine') OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500
  OR p_hash !~ '^[0-9a-f]{64}$' THEN RAISE EXCEPTION 'Invalid condition or reason' USING ERRCODE='23514'; END IF;
 SELECT * INTO existing FROM pos_lot_condition_events WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF existing.request_hash<>p_hash OR existing.actor_id<>p_actor OR existing.lot_id<>p_lot
   THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN existing.id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO l FROM pos_stock_lots WHERE id=p_lot AND organization_id=p_org AND branch_id=p_branch FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Lot unavailable' USING ERRCODE='23514'; END IF;
 IF l.condition=p_condition OR l.condition IN('damaged','expired') THEN
  RAISE EXCEPTION 'Invalid condition transition' USING ERRCODE='23514'; END IF;
 IF p_condition='sellable' THEN
  SELECT (clock_timestamp() AT TIME ZONE timezone)::date INTO local_date FROM branches WHERE id=p_branch AND organization_id=p_org;
  IF l.expires_on IS NOT NULL AND l.expires_on<local_date THEN
   RAISE EXCEPTION 'Expired lot cannot be released' USING ERRCODE='23514'; END IF;
 END IF;
 -- Only this function can write a condition. The existing immutable trigger remains
 -- and is replaced by a guard that verifies every other receipt field stays intact.
 PERFORM set_config('dlc.pos_condition_transition','yes',true);
 UPDATE pos_stock_lots SET condition=p_condition WHERE id=p_lot;
 PERFORM set_config('dlc.pos_condition_transition','',true);
 INSERT INTO pos_lot_condition_events(organization_id,branch_id,lot_id,previous_condition,new_condition,reason,command_id,request_hash,actor_id,correlation_id)
 VALUES(p_org,p_branch,p_lot,l.condition,p_condition,btrim(p_reason),p_command,p_hash,p_actor,p_correlation) RETURNING id INTO event_id;
 RETURN event_id;
END $$;
CREATE FUNCTION guard_pos_lot_update() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF TG_OP='DELETE' OR current_setting('dlc.pos_condition_transition',true) IS DISTINCT FROM 'yes'
  OR (to_jsonb(NEW)-'condition') IS DISTINCT FROM (to_jsonb(OLD)-'condition')
 THEN RAISE EXCEPTION 'POS lot receipt is append-only' USING ERRCODE='55000'; END IF;
 RETURN NEW;
END $$;
DROP TRIGGER pos_fact_immutable ON pos_stock_lots;
CREATE TRIGGER pos_fact_immutable BEFORE UPDATE OR DELETE ON pos_stock_lots FOR EACH ROW EXECUTE FUNCTION guard_pos_lot_update();
REVOKE ALL ON FUNCTION guard_pos_lot_update() FROM PUBLIC,anon,authenticated,service_role;
REVOKE ALL ON FUNCTION set_pos_lot_condition(uuid,uuid,uuid,uuid,text,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION set_pos_lot_condition(uuid,uuid,uuid,uuid,text,text,uuid,text,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('pos.stock.quarantine','Inmovilizar o liberar un lote de tienda') ON CONFLICT(code) DO NOTHING;
