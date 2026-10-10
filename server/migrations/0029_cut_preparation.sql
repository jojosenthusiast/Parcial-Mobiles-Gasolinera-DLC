-- Policy versions and preparation evidence remain immutable after use.
CREATE TABLE operational_cut_reconciliation_policies (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 effective_date date NOT NULL, meter_tolerance_l numeric(18,6) NOT NULL CHECK(meter_tolerance_l>=0),
 tank_tolerance_l numeric(18,6) NOT NULL CHECK(tank_tolerance_l>=0),
 collection_tolerance_usd numeric(18,2) NOT NULL CHECK(collection_tolerance_usd>=0),
 auto_close_enabled boolean NOT NULL DEFAULT false, created_by uuid NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(branch_id,effective_date), UNIQUE(id,organization_id,branch_id)
);
CREATE TRIGGER cut_reconciliation_policies_immutable BEFORE UPDATE OR DELETE ON operational_cut_reconciliation_policies
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE TABLE operational_cut_preparations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), cut_id uuid NOT NULL UNIQUE, organization_id uuid NOT NULL, branch_id uuid NOT NULL,
 policy_id uuid NOT NULL, input_version integer NOT NULL, output_version integer NOT NULL,
 product_summary jsonb NOT NULL, tank_summary jsonb NOT NULL, financial_summary jsonb NOT NULL,
 review_required boolean NOT NULL, blocking_issues jsonb NOT NULL DEFAULT '[]', warnings jsonb NOT NULL DEFAULT '[]',
 prepared_by uuid NOT NULL, prepared_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(cut_id,organization_id,branch_id) REFERENCES operational_cuts(id,organization_id,branch_id),
 FOREIGN KEY(policy_id,organization_id,branch_id) REFERENCES operational_cut_reconciliation_policies(id,organization_id,branch_id),
 FOREIGN KEY(prepared_by,organization_id) REFERENCES users(id,organization_id),
 CHECK(output_version=input_version+1),
 CHECK(jsonb_typeof(product_summary)='array' AND jsonb_typeof(tank_summary)='array' AND jsonb_typeof(financial_summary)='object'),
 CHECK(jsonb_typeof(blocking_issues)='array' AND jsonb_typeof(warnings)='array')
);
CREATE TRIGGER cut_preparations_immutable BEFORE UPDATE OR DELETE ON operational_cut_preparations
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE INDEX cut_preparation_branch_idx ON operational_cut_preparations(branch_id,prepared_at DESC);

CREATE FUNCTION prepare_operational_cut(org uuid, branch uuid, target_cut uuid, actor uuid, expected_version integer)
 RETURNS TABLE(preparation_id uuid,version integer,review_required boolean)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c operational_cuts%ROWTYPE; pol operational_cut_reconciliation_policies%ROWTYPE;
 products jsonb; tank_levels jsonb; finance jsonb; requires_review boolean; pid uuid;
BEGIN
 SELECT oc.* INTO c FROM operational_cuts oc WHERE oc.id=target_cut AND oc.organization_id=org AND oc.branch_id=branch FOR UPDATE;
 IF c.id IS NULL OR c.status<>'open' OR c.version<>expected_version THEN
  RAISE EXCEPTION 'Cut not open or version changed' USING ERRCODE='40001'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive preparer' USING ERRCODE='23514'; END IF;
 SELECT p.* INTO pol FROM operational_cut_reconciliation_policies p WHERE p.branch_id=branch AND p.organization_id=org
  AND p.effective_date<=c.operational_date ORDER BY p.effective_date DESC LIMIT 1;
 IF pol.id IS NULL THEN RAISE EXCEPTION 'Reconciliation policy is missing' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM operational_cut_nozzles n LEFT JOIN operational_cut_meter_captures m ON m.cut_id=n.cut_id AND m.nozzle_id=n.nozzle_id
  WHERE n.cut_id=target_cut AND n.participation='expected' AND m.reading_id IS NULL) THEN
  RAISE EXCEPTION 'Expected nozzle readings are missing' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM tanks t LEFT JOIN operational_cut_tank_measurements m ON m.cut_id=target_cut AND m.tank_id=t.id
  WHERE t.branch_id=branch AND t.organization_id=org AND t.status='active' AND m.tank_id IS NULL) THEN
  RAISE EXCEPTION 'Active tank measurement is missing' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM operational_cut_tank_measurements m WHERE m.cut_id=target_cut AND NOT EXISTS(
  SELECT 1 FROM inventory_movements im WHERE im.tank_id=m.tank_id AND im.organization_id=org AND im.occurred_at<c.ends_at)) THEN
  RAISE EXCEPTION 'Tank has no opening inventory baseline' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM dispense_authorizations a WHERE a.branch_id=branch AND a.organization_id=org AND
  a.created_at<c.ends_at AND a.created_at>=c.starts_at AND a.status IN('authorized','dispensing','unknown','posting')) THEN
  RAISE EXCEPTION 'Unresolved dispatches in the cut window' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM dispense_authorizations a LEFT JOIN sales s ON s.authorization_id=a.id
  WHERE a.branch_id=branch AND a.organization_id=org AND a.status='completed' AND
  a.completed_at>=c.starts_at AND a.completed_at<c.ends_at AND s.id IS NULL) THEN
  RAISE EXCEPTION 'Completed dispatch lacks its sale ticket' USING ERRCODE='23514'; END IF;
 WITH meter AS (SELECT n.fuel_product_id AS product_id,COALESCE(sum(m.measured_l),0) AS liters
  FROM operational_cut_nozzles n LEFT JOIN operational_cut_meter_captures m ON m.cut_id=n.cut_id AND m.nozzle_id=n.nozzle_id
  WHERE n.cut_id=target_cut GROUP BY n.fuel_product_id),
 sold AS (SELECT a.fuel_product_id AS product_id,sum(a.actual_l) AS liters,sum(a.sale_amount_usd) AS usd
  FROM dispense_authorizations a WHERE a.branch_id=branch AND a.organization_id=org AND a.status='completed'
  AND a.completed_at>=c.starts_at AND a.completed_at<c.ends_at GROUP BY a.fuel_product_id),
 stock AS (SELECT im.fuel_product_id AS product_id,
   COALESCE(sum(im.delta_l) FILTER(WHERE im.movement_type='receipt'),0) AS receipts_l,
   COALESCE(-sum(im.delta_l) FILTER(WHERE im.movement_type='loss'),0) AS losses_l
  FROM inventory_movements im WHERE im.branch_id=branch AND im.organization_id=org
  AND im.occurred_at>=c.starts_at AND im.occurred_at<c.ends_at GROUP BY im.fuel_product_id),
 combined AS (SELECT COALESCE(m.product_id,s.product_id,st.product_id) AS product_id,
  COALESCE(m.liters,0) AS measured_l,COALESCE(s.liters,0) AS sold_l,COALESCE(s.usd,0) AS sales_usd,
  COALESCE(st.receipts_l,0) AS receipts_l,COALESCE(st.losses_l,0) AS losses_l
  FROM meter m FULL JOIN sold s ON m.product_id=s.product_id FULL JOIN stock st ON st.product_id=COALESCE(m.product_id,s.product_id))
 SELECT COALESCE(jsonb_agg(jsonb_build_object('fuelProductId',product_id,'meterLiters',measured_l,'soldLiters',sold_l,
  'salesUsd',sales_usd,'receiptsLiters',receipts_l,'lossLiters',losses_l,'varianceLiters',measured_l-sold_l)
  ORDER BY product_id),'[]'::jsonb),COALESCE(bool_or(abs(measured_l-sold_l)>pol.meter_tolerance_l),false)
 INTO products,requires_review FROM combined;
 WITH levels AS (SELECT m.tank_id,m.fuel_product_id,m.measured_l,
  (SELECT im.after_quantity_l FROM inventory_movements im WHERE im.tank_id=m.tank_id AND im.organization_id=org
   AND im.occurred_at<c.ends_at ORDER BY im.occurred_at DESC,im.id DESC LIMIT 1) AS ledger_l
  FROM operational_cut_tank_measurements m WHERE m.cut_id=target_cut)
 SELECT COALESCE(jsonb_agg(jsonb_build_object('tankId',tank_id,'fuelProductId',fuel_product_id,
  'measuredLiters',measured_l,'ledgerLiters',ledger_l,'varianceLiters',measured_l-ledger_l) ORDER BY tank_id),'[]'::jsonb),
  COALESCE(bool_or(ledger_l IS NULL OR abs(measured_l-ledger_l)>pol.tank_tolerance_l),false) OR requires_review
 INTO tank_levels,requires_review FROM levels;
 -- Payment is attributed to the original sale in this window, irrespective of when it was collected.
 SELECT jsonb_build_object('salesUsd',COALESCE((SELECT sum(s.total_usd) FROM sales s WHERE s.branch_id=branch AND
   s.organization_id=org AND s.occurred_at>=c.starts_at AND s.occurred_at<c.ends_at),0),
  'confirmedCollectionUsd',COALESCE((SELECT sum(a.amount_usd) FROM payment_attempts a JOIN payment_events e
    ON e.attempt_id=a.id AND e.outcome='confirmed' JOIN sales s ON s.id=a.sale_id
    WHERE s.branch_id=branch AND s.organization_id=org AND s.occurred_at>=c.starts_at AND s.occurred_at<c.ends_at),0),
  'refundedUsd',COALESCE((SELECT sum(r.amount_usd) FROM payment_refunds r JOIN payment_events e ON e.id=r.payment_event_id
    JOIN payment_attempts a ON a.id=e.attempt_id JOIN sales s ON s.id=a.sale_id
    WHERE s.branch_id=branch AND s.organization_id=org AND s.occurred_at>=c.starts_at AND s.occurred_at<c.ends_at),0))
 INTO finance;
 requires_review:=requires_review OR
  abs((finance->>'salesUsd')::numeric-(finance->>'confirmedCollectionUsd')::numeric+(finance->>'refundedUsd')::numeric)>pol.collection_tolerance_usd;
 INSERT INTO operational_cut_preparations(cut_id,organization_id,branch_id,policy_id,input_version,output_version,
  product_summary,tank_summary,financial_summary,review_required,prepared_by)
 VALUES(target_cut,org,branch,pol.id,expected_version,expected_version+1,products,tank_levels,finance,requires_review,actor)
 RETURNING id INTO pid;
 UPDATE operational_cuts oc SET status=CASE WHEN requires_review THEN 'inReview' ELSE 'prepared' END,version=oc.version+1
  WHERE oc.id=target_cut;
 RETURN QUERY SELECT pid,expected_version+1,requires_review;
END; $$;

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['operational_cut_reconciliation_policies','operational_cut_preparations'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('REVOKE ALL ON TABLE %I FROM PUBLIC,anon,authenticated,service_role',t);
  EXECUTE format('GRANT SELECT,INSERT ON TABLE %I TO dlc_api_runtime',t);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',t);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',t);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION prepare_operational_cut(uuid,uuid,uuid,uuid,integer) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION prepare_operational_cut(uuid,uuid,uuid,uuid,integer) TO dlc_api_runtime;
