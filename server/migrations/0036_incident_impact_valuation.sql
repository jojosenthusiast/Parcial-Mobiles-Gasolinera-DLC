-- Cost recognized from historical inventory and commercial price are separate valuations.
CREATE TABLE incident_impact_assessments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 incident_id uuid NOT NULL,impact_type text NOT NULL CHECK(impact_type IN('fuel_loss','repair','third_party')),
 tank_id uuid,fuel_product_id uuid,quantity_l numeric(24,9),
 cost_source_movement_id uuid,unit_cost_usd_per_l numeric(24,12),
 historical_cost_usd numeric(24,8),cost_quality text NOT NULL CHECK(cost_quality IN('known','unknown','provisional')),
 reference_price_version_id uuid,commercial_reference_usd numeric(24,8),
 repair_estimate_usd numeric(24,2),third_party_estimate_usd numeric(24,2),
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 8 AND 1000),assessed_by uuid NOT NULL,assessed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(incident_id,organization_id,branch_id) REFERENCES incidents(id,organization_id,branch_id),
 FOREIGN KEY(tank_id,branch_id,fuel_product_id) REFERENCES tanks(id,branch_id,fuel_product_id),
 FOREIGN KEY(cost_source_movement_id) REFERENCES inventory_movements(id),
 FOREIGN KEY(reference_price_version_id) REFERENCES fuel_price_versions(id),
 FOREIGN KEY(assessed_by,organization_id) REFERENCES users(id,organization_id),
 CHECK((impact_type='fuel_loss' AND tank_id IS NOT NULL AND quantity_l>0 AND repair_estimate_usd IS NULL AND third_party_estimate_usd IS NULL)
  OR (impact_type='repair' AND tank_id IS NULL AND fuel_product_id IS NULL AND quantity_l IS NULL AND repair_estimate_usd>=0 AND third_party_estimate_usd IS NULL)
  OR (impact_type='third_party' AND tank_id IS NULL AND fuel_product_id IS NULL AND quantity_l IS NULL AND third_party_estimate_usd>=0 AND repair_estimate_usd IS NULL)),
 CHECK((cost_quality='known' AND unit_cost_usd_per_l IS NOT NULL AND historical_cost_usd IS NOT NULL)
  OR (cost_quality<>'known' AND unit_cost_usd_per_l IS NULL AND historical_cost_usd IS NULL)),
 CHECK(historical_cost_usd IS NULL OR historical_cost_usd>=0),
 CHECK(commercial_reference_usd IS NULL OR commercial_reference_usd>=0)
);
CREATE UNIQUE INDEX incident_one_fuel_assessment_per_tank ON incident_impact_assessments(incident_id,tank_id) WHERE impact_type='fuel_loss';
CREATE UNIQUE INDEX incident_one_nonfuel_assessment_per_type ON incident_impact_assessments(incident_id,impact_type) WHERE impact_type<>'fuel_loss';
CREATE TRIGGER incident_impact_assessments_immutable BEFORE UPDATE OR DELETE ON incident_impact_assessments
 FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();

CREATE FUNCTION assess_incident_impact(org uuid,branch uuid,target_incident uuid,actor uuid,kind text,
 target_tank uuid,liters numeric,mode text,estimate numeric,assessment_note text)
 RETURNS TABLE(assessment_id uuid,historical_cost_usd numeric,commercial_reference_usd numeric,cost_quality text)
 LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE i incidents%ROWTYPE; t tanks%ROWTYPE; movement inventory_movements%ROWTYPE; price fuel_price_versions%ROWTYPE;
 aid uuid; quality text; cost numeric; commercial numeric;
BEGIN
 SELECT x.* INTO i FROM incidents x WHERE x.id=target_incident AND x.branch_id=branch AND x.organization_id=org FOR UPDATE;
 IF i.id IS NULL OR i.status IN('resolved','closed') THEN RAISE EXCEPTION 'Incident not assessable' USING ERRCODE='23514'; END IF;
 IF NOT EXISTS(SELECT 1 FROM users u WHERE u.id=actor AND u.organization_id=org AND u.status='active') THEN
  RAISE EXCEPTION 'Inactive assessor' USING ERRCODE='23514'; END IF;
 IF kind='fuel_loss' THEN
  SELECT x.* INTO t FROM tanks x WHERE x.id=target_tank AND x.branch_id=branch AND x.organization_id=org;
  IF t.id IS NULL OR liters IS NULL OR liters<=0 OR estimate IS NOT NULL OR mode NOT IN('full_service','self_service') THEN
   RAISE EXCEPTION 'Fuel loss needs a tank, volume and reference service mode' USING ERRCODE='23514'; END IF;
  SELECT x.* INTO movement FROM inventory_movements x WHERE x.tank_id=t.id AND x.organization_id=org AND x.occurred_at<=i.occurred_at
    ORDER BY x.occurred_at DESC,x.id DESC LIMIT 1;
  IF movement.id IS NULL OR movement.after_quantity_l<liters THEN
   RAISE EXCEPTION 'Fuel loss exceeds historical stock or lacks an opening baseline' USING ERRCODE='23514'; END IF;
  quality:=CASE WHEN movement.valuation_quality='known' AND movement.unit_cost_usd_per_l IS NOT NULL THEN 'known' ELSE 'unknown' END;
  cost:=CASE WHEN quality='known' THEN round(liters*movement.unit_cost_usd_per_l,8) ELSE NULL END;
  SELECT x.* INTO price FROM fuel_price_versions x WHERE x.organization_id=org AND x.branch_id=branch AND
   x.fuel_product_id=t.fuel_product_id AND x.service_mode=mode AND x.effective_at<=i.occurred_at
   ORDER BY x.effective_at DESC,x.version DESC LIMIT 1;
  commercial:=CASE WHEN price.id IS NOT NULL THEN round(liters*price.price_usd_per_unit/
   CASE WHEN price.unit='us_gallon' THEN 3.785411784 ELSE 1 END,8) ELSE NULL END;
  INSERT INTO incident_impact_assessments(organization_id,branch_id,incident_id,impact_type,tank_id,fuel_product_id,
   quantity_l,cost_source_movement_id,unit_cost_usd_per_l,historical_cost_usd,cost_quality,reference_price_version_id,
   commercial_reference_usd,note,assessed_by)
  VALUES(org,branch,target_incident,kind,t.id,t.fuel_product_id,liters,movement.id,
   CASE WHEN quality='known' THEN movement.unit_cost_usd_per_l ELSE NULL END,cost,quality,price.id,commercial,assessment_note,actor)
  RETURNING id INTO aid;
 ELSIF kind IN('repair','third_party') THEN
  IF target_tank IS NOT NULL OR liters IS NOT NULL OR mode IS NOT NULL OR estimate IS NULL OR estimate<0 THEN
   RAISE EXCEPTION 'Non-fuel damage cannot include fuel quantity or a price mode' USING ERRCODE='23514'; END IF;
  quality:='unknown';
  INSERT INTO incident_impact_assessments(organization_id,branch_id,incident_id,impact_type,
   cost_quality,repair_estimate_usd,third_party_estimate_usd,note,assessed_by)
  VALUES(org,branch,target_incident,kind,quality,CASE WHEN kind='repair' THEN estimate ELSE NULL END,
   CASE WHEN kind='third_party' THEN estimate ELSE NULL END,assessment_note,actor) RETURNING id INTO aid;
 ELSE RAISE EXCEPTION 'Invalid impact type' USING ERRCODE='23514'; END IF;
 RETURN QUERY SELECT aid,cost,commercial,quality;
END; $$;
ALTER TABLE incident_impact_assessments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE incident_impact_assessments FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT ON TABLE incident_impact_assessments TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON incident_impact_assessments FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON incident_impact_assessments FOR INSERT TO dlc_api_runtime WITH CHECK(true);
REVOKE ALL ON FUNCTION assess_incident_impact(uuid,uuid,uuid,uuid,text,uuid,numeric,text,numeric,text) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION assess_incident_impact(uuid,uuid,uuid,uuid,text,uuid,numeric,text,numeric,text) TO dlc_api_runtime;
