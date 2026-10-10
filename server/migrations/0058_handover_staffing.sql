-- Handovers acknowledge unresolved work; no automatic cash ownership or extra fuel cut.
CREATE TABLE employee_shift_handovers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 outgoing_shift_id uuid NOT NULL,incoming_shift_id uuid NOT NULL,
 pending_items jsonb NOT NULL CHECK(jsonb_typeof(pending_items)='array' AND jsonb_array_length(pending_items)<=30),
 equipment_note text NOT NULL CHECK(length(btrim(equipment_note)) BETWEEN 5 AND 500),
 cash_session_id uuid,observed_cash_usd numeric(18,2) CHECK(observed_cash_usd>=0),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 handed_by uuid NOT NULL,handed_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(outgoing_shift_id,organization_id,branch_id) REFERENCES employee_work_shifts(id,organization_id,branch_id),
 FOREIGN KEY(incoming_shift_id,organization_id,branch_id) REFERENCES employee_work_shifts(id,organization_id,branch_id),
 FOREIGN KEY(cash_session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
 FOREIGN KEY(handed_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(outgoing_shift_id<>incoming_shift_id),
 CHECK((cash_session_id IS NULL AND observed_cash_usd IS NULL) OR (cash_session_id IS NOT NULL AND observed_cash_usd IS NOT NULL)),
 UNIQUE(organization_id,command_id),UNIQUE(outgoing_shift_id,incoming_shift_id),UNIQUE(id,organization_id,branch_id)
);
CREATE TABLE employee_handover_acknowledgments (
 handover_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 5 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 received_by uuid NOT NULL,received_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(handover_id,organization_id,branch_id) REFERENCES employee_shift_handovers(id,organization_id,branch_id),
 FOREIGN KEY(received_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id)
);
CREATE FUNCTION validate_shift_handover() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE outgoing employee_work_shifts%ROWTYPE; incoming employee_work_shifts%ROWTYPE;
BEGIN
 SELECT * INTO outgoing FROM employee_work_shifts WHERE id=NEW.outgoing_shift_id;
 SELECT * INTO incoming FROM employee_work_shifts WHERE id=NEW.incoming_shift_id;
 IF outgoing.status<>'scheduled' OR incoming.status<>'scheduled'
  OR outgoing.branch_id<>incoming.branch_id OR outgoing.organization_id<>incoming.organization_id
  OR outgoing.employee_id=incoming.employee_id OR NEW.organization_id<>outgoing.organization_id OR NEW.branch_id<>outgoing.branch_id
  OR incoming.starts_at<outgoing.starts_at OR incoming.starts_at>outgoing.ends_at+interval '4 hours'
  OR NOT EXISTS(SELECT 1 FROM users WHERE id=NEW.handed_by AND employee_id=outgoing.employee_id AND status='active')
  OR NOT EXISTS(SELECT 1 FROM employee_attendance_events WHERE shift_id=outgoing.id AND kind='clock_in')
  OR NOT EXISTS(SELECT 1 FROM employee_attendance_events WHERE shift_id=incoming.id AND kind='clock_in')
 THEN RAISE EXCEPTION 'Handover requires two attending shifts in the same branch' USING ERRCODE='23514'; END IF;
 IF NEW.cash_session_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM cash_sessions cs
  JOIN users u ON u.id=cs.cashier_id WHERE cs.id=NEW.cash_session_id AND u.employee_id=outgoing.employee_id)
 THEN RAISE EXCEPTION 'Observed cash does not belong to outgoing cashier' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER handover_guard BEFORE INSERT ON employee_shift_handovers FOR EACH ROW EXECUTE FUNCTION validate_shift_handover();
CREATE FUNCTION validate_handover_ack() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE h employee_shift_handovers%ROWTYPE; s employee_work_shifts%ROWTYPE;
BEGIN
 SELECT * INTO h FROM employee_shift_handovers WHERE id=NEW.handover_id;
 SELECT * INTO s FROM employee_work_shifts WHERE id=h.incoming_shift_id;
 IF h.id IS NULL OR NEW.organization_id<>h.organization_id OR NEW.branch_id<>h.branch_id
  OR NEW.received_by=h.handed_by OR NOT EXISTS(SELECT 1 FROM users u WHERE u.id=NEW.received_by AND u.employee_id=s.employee_id AND u.status='active')
 THEN RAISE EXCEPTION 'Incoming worker must acknowledge the handover' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER handover_ack_guard BEFORE INSERT ON employee_handover_acknowledgments FOR EACH ROW EXECUTE FUNCTION validate_handover_ack();

CREATE TABLE staffing_asset_blocks (
 block_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,dispenser_id uuid NOT NULL,
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 recorded_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(block_id) REFERENCES asset_blocks(id),
 FOREIGN KEY(dispenser_id,branch_id) REFERENCES dispensers(id,branch_id),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id)
);
CREATE TABLE staffing_block_resolutions (
 block_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 resolved_by uuid NOT NULL,resolved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(block_id) REFERENCES staffing_asset_blocks(block_id),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(resolved_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id)
);
CREATE FUNCTION validate_staffing_link() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM asset_blocks b WHERE b.id=NEW.block_id AND b.organization_id=NEW.organization_id
  AND b.branch_id=NEW.branch_id AND b.asset_type='dispenser' AND b.asset_id=NEW.dispenser_id
  AND b.block_type='operational' AND b.reason_code='staffing' AND b.created_by=NEW.recorded_by)
 THEN RAISE EXCEPTION 'Staffing block linkage mismatch' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER staffing_link_guard BEFORE INSERT ON staffing_asset_blocks FOR EACH ROW EXECUTE FUNCTION validate_staffing_link();
CREATE FUNCTION set_staffing_block(p_org uuid,p_branch uuid,p_actor uuid,p_dispenser uuid,p_block boolean,
 p_reason text,p_command uuid,p_hash text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE prior staffing_asset_blocks%ROWTYPE; prior_resolution staffing_block_resolutions%ROWTYPE;
 block_id uuid; active_workers integer;
BEGIN
 IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 OR p_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Staffing reason required' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('staffing-block:'||p_org||':'||p_dispenser,0));
 SELECT * INTO prior FROM staffing_asset_blocks WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF NOT p_block OR prior.request_hash<>p_hash OR prior.recorded_by<>p_actor THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN prior.block_id;
 END IF;
 SELECT * INTO prior_resolution FROM staffing_block_resolutions WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF p_block OR prior_resolution.request_hash<>p_hash OR prior_resolution.resolved_by<>p_actor THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN prior_resolution.block_id;
 END IF;
 IF NOT EXISTS(SELECT 1 FROM dispensers WHERE id=p_dispenser AND branch_id=p_branch AND organization_id=p_org)
  OR NOT EXISTS(SELECT 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active')
 THEN RAISE EXCEPTION 'Dispenser or actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT count(*) INTO active_workers FROM employee_work_shifts s
 JOIN employee_shift_attendance a ON a.shift_id=s.id
 WHERE s.dispenser_id=p_dispenser AND s.status='scheduled' AND s.position='forecourt'
  AND s.starts_at<=clock_timestamp() AND s.ends_at>clock_timestamp()
  AND a.clocked_in_at IS NOT NULL AND a.clocked_out_at IS NULL;
 IF p_block THEN
  IF active_workers>0 THEN RAISE EXCEPTION 'Dispenser currently has staff' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM staffing_asset_blocks x JOIN asset_blocks b ON b.id=x.block_id
   WHERE x.dispenser_id=p_dispenser AND b.resolved_at IS NULL)
  THEN RAISE EXCEPTION 'Staffing block already active' USING ERRCODE='23514'; END IF;
  INSERT INTO asset_blocks(organization_id,branch_id,asset_type,asset_id,block_type,reason_code,reason,created_by)
  VALUES(p_org,p_branch,'dispenser',p_dispenser,'operational','staffing',btrim(p_reason),p_actor)
  RETURNING id INTO block_id;
  INSERT INTO staffing_asset_blocks(block_id,organization_id,branch_id,dispenser_id,command_id,request_hash,recorded_by)
  VALUES(block_id,p_org,p_branch,p_dispenser,p_command,p_hash,p_actor);
 ELSE
  IF active_workers=0 THEN RAISE EXCEPTION 'No attending worker to restore operation' USING ERRCODE='23514'; END IF;
  SELECT x.block_id INTO block_id FROM staffing_asset_blocks x JOIN asset_blocks b ON b.id=x.block_id
  WHERE x.dispenser_id=p_dispenser AND x.organization_id=p_org AND b.resolved_at IS NULL FOR UPDATE OF b;
  IF block_id IS NULL THEN RAISE EXCEPTION 'No active staffing block' USING ERRCODE='23514'; END IF;
  UPDATE asset_blocks SET resolved_by=p_actor,resolved_at=clock_timestamp(),resolution=btrim(p_reason) WHERE id=block_id;
  INSERT INTO staffing_block_resolutions(block_id,organization_id,branch_id,command_id,request_hash,resolved_by)
  VALUES(block_id,p_org,p_branch,p_command,p_hash,p_actor);
 END IF;
 RETURN block_id;
END $$;
DO $$ DECLARE tab text; fn regprocedure; BEGIN
 FOREACH tab IN ARRAY ARRAY['employee_shift_handovers','employee_handover_acknowledgments','staffing_asset_blocks','staffing_block_resolutions'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',tab);
  EXECUTE format('GRANT SELECT ON %I TO dlc_api_runtime',tab);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',tab);
  EXECUTE format('CREATE TRIGGER handover_fact_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',tab);
 END LOOP;
END $$;
GRANT INSERT ON employee_shift_handovers,employee_handover_acknowledgments TO dlc_api_runtime;
CREATE POLICY dlc_api_insert ON employee_shift_handovers FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_insert ON employee_handover_acknowledgments FOR INSERT TO dlc_api_runtime WITH CHECK(true);
REVOKE ALL ON FUNCTION set_staffing_block(uuid,uuid,uuid,uuid,boolean,text,uuid,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION set_staffing_block(uuid,uuid,uuid,uuid,boolean,text,uuid,text) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('staff.handover','Registrar y confirmar relevo de personal'),
 ('staff.staffing.block','Inmovilizar o reabrir posición por falta de personal') ON CONFLICT(code) DO NOTHING;
