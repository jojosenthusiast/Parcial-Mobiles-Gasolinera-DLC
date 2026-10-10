-- An approved shortage can be classified without re-posting stock.
CREATE TABLE store_stock_loss_classifications (
 count_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 cause text NOT NULL CHECK(cause IN('damage','expired','suspected_theft','unexplained')),
 quantity_units integer NOT NULL CHECK(quantity_units>0),
 cost_usd numeric(18,2),cost_quality text NOT NULL CHECK(cost_quality IN('known','unknown')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 classified_by uuid NOT NULL,classified_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(count_id,organization_id,branch_id) REFERENCES store_count_approvals(count_id,organization_id,branch_id),
 FOREIGN KEY(classified_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id),
 CHECK((cost_quality='unknown' AND cost_usd IS NULL) OR (cost_quality='known' AND cost_usd IS NOT NULL))
);
CREATE FUNCTION classify_store_stock_loss(p_org uuid,p_branch uuid,p_actor uuid,p_count uuid,p_cause text,
 p_reason text,p_command uuid,p_hash text,p_correlation uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old store_stock_loss_classifications%ROWTYPE; a store_count_approvals%ROWTYPE; l pos_stock_lots%ROWTYPE;
BEGIN
 IF p_cause NOT IN('damage','expired','suspected_theft','unexplained')
  OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 10 AND 500 OR p_hash !~ '^[0-9a-f]{64}$'
 THEN RAISE EXCEPTION 'Invalid loss classification' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended('store-loss:'||p_org||':'||p_command,0));
 SELECT * INTO old FROM store_stock_loss_classifications WHERE organization_id=p_org AND command_id=p_command;
 IF FOUND THEN
  IF old.request_hash<>p_hash OR old.classified_by<>p_actor OR old.count_id<>p_count
   THEN RAISE EXCEPTION 'Command was reused' USING ERRCODE='23514'; END IF;
  RETURN old.count_id;
 END IF;
 PERFORM 1 FROM users WHERE id=p_actor AND organization_id=p_org AND status='active';
 IF NOT FOUND THEN RAISE EXCEPTION 'Actor unavailable' USING ERRCODE='23514'; END IF;
 SELECT * INTO a FROM store_count_approvals WHERE count_id=p_count AND organization_id=p_org AND branch_id=p_branch;
 SELECT l0.* INTO l FROM store_stock_counts c JOIN pos_stock_lots l0 ON l0.id=c.lot_id WHERE c.id=p_count;
 IF a.count_id IS NULL OR a.delta_units>=0 OR l.id IS NULL
  OR EXISTS(SELECT 1 FROM store_stock_loss_classifications WHERE count_id=p_count)
 THEN RAISE EXCEPTION 'Only one loss classification per approved shortage' USING ERRCODE='23514'; END IF;
 INSERT INTO store_stock_loss_classifications(count_id,organization_id,branch_id,cause,quantity_units,cost_usd,cost_quality,
  reason,command_id,request_hash,classified_by,correlation_id)
 VALUES(p_count,p_org,p_branch,p_cause,-a.delta_units,
  CASE WHEN l.unit_cost_usd IS NULL THEN NULL ELSE round(-a.delta_units*l.unit_cost_usd,2) END,
  CASE WHEN l.unit_cost_usd IS NULL THEN 'unknown' ELSE 'known' END,
  btrim(p_reason),p_command,p_hash,p_actor,p_correlation);
 RETURN p_count;
END $$;
ALTER TABLE store_stock_loss_classifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON store_stock_loss_classifications FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON store_stock_loss_classifications TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON store_stock_loss_classifications FOR SELECT TO dlc_api_runtime USING(true);
CREATE TRIGGER store_loss_immutable BEFORE UPDATE OR DELETE ON store_stock_loss_classifications FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION classify_store_stock_loss(uuid,uuid,uuid,uuid,text,text,uuid,text,uuid) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION classify_store_stock_loss(uuid,uuid,uuid,uuid,text,text,uuid,text,uuid) TO dlc_api_runtime;
INSERT INTO permissions(code,description) VALUES('pos.stock.loss.classify','Clasificar y valorar merma de tienda aprobada') ON CONFLICT(code) DO NOTHING;
