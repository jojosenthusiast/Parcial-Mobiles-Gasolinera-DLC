CREATE TABLE anomaly_alerts (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 cut_id uuid NOT NULL,preparation_id uuid NOT NULL,
 rule_code text NOT NULL CHECK(rule_code IN('meter_variance','tank_variance','collection_variance')),
 asset_key text NOT NULL,observation jsonb NOT NULL CHECK(jsonb_typeof(observation)='object'),
 status text NOT NULL DEFAULT 'open' CHECK(status IN('open','investigating','dismissed','confirmed_loss')),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),reviewed_by uuid,reviewed_at timestamptz,review_note text,
 FOREIGN KEY(cut_id,organization_id,branch_id) REFERENCES operational_cuts(id,organization_id,branch_id),
 FOREIGN KEY(preparation_id) REFERENCES operational_cut_preparations(id),
 FOREIGN KEY(reviewed_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(preparation_id,rule_code,asset_key),
 CHECK((reviewed_by IS NULL AND reviewed_at IS NULL AND review_note IS NULL) OR
  (reviewed_by IS NOT NULL AND reviewed_at IS NOT NULL AND length(btrim(review_note)) BETWEEN 8 AND 500))
);
CREATE INDEX anomaly_alerts_branch_queue_idx ON anomaly_alerts(organization_id,branch_id,status,created_at DESC);
CREATE FUNCTION materialize_cut_anomalies() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE warning jsonb; key text; code text;
BEGIN
 FOR warning IN SELECT value FROM jsonb_array_elements(NEW.warnings) LOOP
  code:=warning->>'code';
  key:=COALESCE(warning->>'tankId',warning->>'fuelProductId','collection');
  INSERT INTO anomaly_alerts(organization_id,branch_id,cut_id,preparation_id,rule_code,asset_key,observation)
   VALUES(NEW.organization_id,NEW.branch_id,NEW.cut_id,NEW.id,code,key,warning);
 END LOOP;
 RETURN NEW;
END; $$;
CREATE TRIGGER cut_preparation_anomaly AFTER INSERT ON operational_cut_preparations
 FOR EACH ROW EXECUTE FUNCTION materialize_cut_anomalies();
CREATE FUNCTION guard_anomaly_update() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF OLD.status IN('dismissed','confirmed_loss') OR
  NEW.id<>OLD.id OR NEW.organization_id<>OLD.organization_id OR NEW.branch_id<>OLD.branch_id OR
  NEW.cut_id<>OLD.cut_id OR NEW.preparation_id<>OLD.preparation_id OR NEW.rule_code<>OLD.rule_code OR
  NEW.asset_key<>OLD.asset_key OR NEW.observation<>OLD.observation THEN
  RAISE EXCEPTION 'Alert source is immutable and final decisions cannot be changed' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER anomaly_update_guard BEFORE UPDATE ON anomaly_alerts FOR EACH ROW EXECUTE FUNCTION guard_anomaly_update();
CREATE FUNCTION review_anomaly(org uuid,branch uuid,target_alert uuid,actor uuid,expected_status text,
 next_status text,note text) RETURNS uuid LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE alert anomaly_alerts%ROWTYPE;
BEGIN
 SELECT a.* INTO alert FROM anomaly_alerts a WHERE a.id=target_alert AND a.organization_id=org AND a.branch_id=branch FOR UPDATE;
 IF alert.id IS NULL OR alert.status<>expected_status OR NOT (
  (alert.status='open' AND next_status IN('investigating','dismissed','confirmed_loss')) OR
  (alert.status='investigating' AND next_status IN('dismissed','confirmed_loss'))) THEN
  RAISE EXCEPTION 'Invalid anomaly review transition' USING ERRCODE='40001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive reviewer' USING ERRCODE='23514'; END IF;
 UPDATE anomaly_alerts a SET status=next_status,reviewed_by=actor,reviewed_at=clock_timestamp(),review_note=note WHERE a.id=target_alert;
 RETURN target_alert;
END; $$;
ALTER TABLE anomaly_alerts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE anomaly_alerts FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE ON TABLE anomaly_alerts TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON anomaly_alerts FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON anomaly_alerts FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_update ON anomaly_alerts FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
REVOKE ALL ON FUNCTION materialize_cut_anomalies(),guard_anomaly_update(),review_anomaly(uuid,uuid,uuid,uuid,text,text,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION review_anomaly(uuid,uuid,uuid,uuid,text,text,text) TO dlc_api_runtime;
