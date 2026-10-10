-- Configurable internal tax breakdown. No jurisdictional rates are seeded here.
CREATE FUNCTION valid_fuel_tax_rules(mode text,rules jsonb) RETURNS boolean LANGUAGE plpgsql IMMUTABLE SET search_path=public,pg_temp AS $$
DECLARE r jsonb; codes text[] := '{}';
BEGIN
 IF mode IS NULL OR mode NOT IN('included','exempt','unconfigured') OR rules IS NULL OR jsonb_typeof(rules)<>'array' THEN RETURN false; END IF;
 IF jsonb_array_length(rules)>8 OR (mode='included') IS DISTINCT FROM (jsonb_array_length(rules)>0) THEN RETURN false; END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(rules) LOOP
  IF jsonb_typeof(r)<>'object' THEN RETURN false; END IF;
  IF (SELECT count(*) FROM jsonb_object_keys(r))<>5 OR NOT r ?& ARRAY['code','label','kind','base','rate'] THEN RETURN false; END IF;
  IF jsonb_typeof(r->'code')<>'string' OR (r->>'code')!~'^[A-Z][A-Z0-9_]{0,23}$' OR (r->>'code')=ANY(codes) THEN RETURN false; END IF;
  codes := array_append(codes,r->>'code');
  IF jsonb_typeof(r->'label')<>'string' OR length(btrim(r->>'label'))=0 OR length(r->>'label')>120 THEN RETURN false; END IF;
  IF jsonb_typeof(r->'rate')<>'string' OR (r->>'rate')!~'^(0|[1-9][0-9]{0,11})(\.[0-9]{1,12})?$' THEN RETURN false; END IF;
  IF (r->>'rate')::numeric<=0 THEN RETURN false; END IF;
  IF jsonb_typeof(r->'kind')<>'string' OR jsonb_typeof(r->'base')<>'string' THEN RETURN false; END IF;
  IF (r->>'kind')='percentage' THEN
   IF (r->>'base') NOT IN('net','net_plus_fixed') OR (r->>'rate')::numeric>1 THEN RETURN false; END IF;
  ELSIF (r->>'kind') IN('fixed_per_liter','fixed_per_us_gallon') THEN
   IF (r->>'base')<>'observed_volume' THEN RETURN false; END IF;
  ELSE RETURN false;
  END IF;
 END LOOP;
 RETURN true;
END; $$;

CREATE FUNCTION calculate_fuel_tax(gross numeric,liters numeric,mode text,rules jsonb) RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=public,pg_temp AS $$
DECLARE r jsonb; fixed numeric:=0; rates numeric:=0; rates_fixed numeric:=0;
 raw_net numeric; component_tax numeric; tax numeric:=0; base numeric; components jsonb:='[]';
BEGIN
 IF NOT valid_fuel_tax_rules(mode,rules) OR gross IS NULL OR liters IS NULL OR gross<0 OR gross<>round(gross,2) OR liters<=0
   OR gross::text IN('NaN','Infinity','-Infinity') OR liters::text IN('NaN','Infinity','-Infinity') THEN
  RAISE EXCEPTION 'Invalid fuel tax calculation' USING ERRCODE='23514';
 END IF;
 IF mode='unconfigured' THEN RETURN jsonb_build_object('status','unconfigured','netUsd',NULL,'taxUsd',NULL,'components','[]'::jsonb); END IF;
 IF mode='exempt' THEN RETURN jsonb_build_object('status','configured','netUsd',round(gross,2)::text,'taxUsd','0.00','components','[]'::jsonb); END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(rules) LOOP
  IF (r->>'kind')='percentage' THEN
   rates:=rates+(r->>'rate')::numeric;
   IF (r->>'base')='net_plus_fixed' THEN rates_fixed:=rates_fixed+(r->>'rate')::numeric; END IF;
  ELSE fixed:=fixed+(CASE WHEN (r->>'kind')='fixed_per_liter' THEN liters ELSE liters/3.785411784 END)*(r->>'rate')::numeric;
  END IF;
 END LOOP;
 raw_net:=(gross-fixed*(1+rates_fixed))/(1+rates);
 IF raw_net<0 THEN RAISE EXCEPTION 'Fixed taxes exceed sale total' USING ERRCODE='23514'; END IF;
 FOR r IN SELECT value FROM jsonb_array_elements(rules) LOOP
  base:=CASE WHEN (r->>'kind')='percentage' THEN raw_net+(CASE WHEN (r->>'base')='net_plus_fixed' THEN fixed ELSE 0 END)
     WHEN (r->>'kind')='fixed_per_liter' THEN liters ELSE liters/3.785411784 END;
  component_tax:=round(base*(r->>'rate')::numeric,2);tax:=tax+component_tax;
  components:=components || (r || jsonb_build_object('taxUsd',component_tax::text));
 END LOOP;
 IF tax>gross THEN RAISE EXCEPTION 'Rounded taxes exceed sale total' USING ERRCODE='23514'; END IF;
 RETURN jsonb_build_object('status','configured','netUsd',round(gross-tax,2)::text,'taxUsd',round(tax,2)::text,'components',components);
END; $$;

CREATE TABLE fuel_tax_proposals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, fuel_product_id uuid NOT NULL,
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 mode text NOT NULL, rules jsonb NOT NULL, source_reference text NOT NULL CHECK(length(btrim(source_reference)) BETWEEN 1 AND 500),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 1 AND 500), effective_at timestamptz NOT NULL,
 proposed_by uuid NOT NULL, proposed_at timestamptz NOT NULL DEFAULT now(), correlation_id uuid NOT NULL,
 CHECK(valid_fuel_tax_rules(mode,rules)), CHECK(effective_at>proposed_at),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(fuel_product_id,organization_id) REFERENCES fuel_products(id,organization_id),
 FOREIGN KEY(proposed_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id), UNIQUE(id,organization_id,branch_id,fuel_product_id)
);
CREATE TABLE fuel_tax_versions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, fuel_product_id uuid NOT NULL,
 proposal_id uuid NOT NULL UNIQUE, version integer NOT NULL CHECK(version>0),
 command_id uuid NOT NULL, request_hash char(64) NOT NULL CHECK(request_hash ~ '^[0-9a-f]{64}$'),
 mode text NOT NULL, rules jsonb NOT NULL, source_reference text NOT NULL, effective_at timestamptz NOT NULL,
 approved_by uuid NOT NULL, approved_at timestamptz NOT NULL DEFAULT now(), correlation_id uuid NOT NULL,
 CHECK(valid_fuel_tax_rules(mode,rules)), CHECK(effective_at>approved_at),
 FOREIGN KEY(proposal_id,organization_id,branch_id,fuel_product_id) REFERENCES fuel_tax_proposals(id,organization_id,branch_id,fuel_product_id),
 FOREIGN KEY(approved_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id), UNIQUE(organization_id,branch_id,fuel_product_id,version),
 UNIQUE(organization_id,branch_id,fuel_product_id,effective_at), UNIQUE(id,organization_id,branch_id)
);
CREATE INDEX fuel_tax_version_effective_idx ON fuel_tax_versions(organization_id,branch_id,fuel_product_id,effective_at DESC);
CREATE INDEX fuel_tax_proposal_branch_idx ON fuel_tax_proposals(organization_id,branch_id,proposed_at DESC);
CREATE TABLE sale_tax_snapshots (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL, branch_id uuid NOT NULL, sale_id uuid NOT NULL UNIQUE,
 policy_version_id uuid NOT NULL, result jsonb NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 FOREIGN KEY(sale_id,organization_id,branch_id) REFERENCES sales(id,organization_id,branch_id),
 FOREIGN KEY(policy_version_id,organization_id,branch_id) REFERENCES fuel_tax_versions(id,organization_id,branch_id),
 CHECK(jsonb_typeof(result)='object')
);
CREATE INDEX sale_tax_policy_idx ON sale_tax_snapshots(policy_version_id);

CREATE FUNCTION validate_fuel_tax_version() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE p fuel_tax_proposals%ROWTYPE;
BEGIN
 SELECT * INTO p FROM fuel_tax_proposals WHERE id=NEW.proposal_id;
 IF p.id IS NULL OR NEW.approved_by=p.proposed_by OR NEW.mode IS DISTINCT FROM p.mode OR NEW.rules IS DISTINCT FROM p.rules
   OR NEW.source_reference IS DISTINCT FROM p.source_reference OR NEW.effective_at IS DISTINCT FROM p.effective_at THEN
  RAISE EXCEPTION 'Tax approval must preserve proposal and use another approver' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER fuel_tax_version_snapshot BEFORE INSERT ON fuel_tax_versions FOR EACH ROW EXECUTE FUNCTION validate_fuel_tax_version();

CREATE FUNCTION validate_sale_tax_snapshot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE s sales%ROWTYPE; a dispense_authorizations%ROWTYPE; p fuel_tax_versions%ROWTYPE; expected_policy uuid;
BEGIN
 SELECT * INTO s FROM sales WHERE id=NEW.sale_id;
 SELECT * INTO a FROM dispense_authorizations WHERE id=s.authorization_id;
 SELECT * INTO p FROM fuel_tax_versions WHERE id=NEW.policy_version_id;
 SELECT id INTO expected_policy FROM fuel_tax_versions WHERE organization_id=s.organization_id AND branch_id=s.branch_id
  AND fuel_product_id=a.fuel_product_id AND effective_at<=s.occurred_at ORDER BY effective_at DESC LIMIT 1;
 IF p.id IS NULL OR p.id IS DISTINCT FROM expected_policy
   OR NEW.result IS DISTINCT FROM calculate_fuel_tax(s.total_usd,a.actual_l,p.mode,p.rules) THEN
  RAISE EXCEPTION 'Tax snapshot differs from applicable approved policy/calculation' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END; $$;
CREATE TRIGGER sale_tax_snapshot_validate BEFORE INSERT ON sale_tax_snapshots FOR EACH ROW EXECUTE FUNCTION validate_sale_tax_snapshot();

-- Only sale creation adds this snapshot. Old tickets are never backfilled by later policies.
CREATE FUNCTION capture_sale_tax_snapshot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE a dispense_authorizations%ROWTYPE; p fuel_tax_versions%ROWTYPE;
BEGIN
 SELECT * INTO a FROM dispense_authorizations WHERE id=NEW.authorization_id;
 SELECT * INTO p FROM fuel_tax_versions WHERE organization_id=NEW.organization_id AND branch_id=NEW.branch_id
  AND fuel_product_id=a.fuel_product_id AND effective_at<=NEW.occurred_at ORDER BY effective_at DESC LIMIT 1;
 IF p.id IS NOT NULL THEN
  INSERT INTO sale_tax_snapshots(organization_id,branch_id,sale_id,policy_version_id,result)
  VALUES(NEW.organization_id,NEW.branch_id,NEW.id,p.id,calculate_fuel_tax(NEW.total_usd,a.actual_l,p.mode,p.rules));
 END IF;
 RETURN NULL;
END; $$;
CREATE TRIGGER sales_capture_tax AFTER INSERT ON sales FOR EACH ROW EXECUTE FUNCTION capture_sale_tax_snapshot();
CREATE TRIGGER fuel_tax_proposals_immutable BEFORE UPDATE OR DELETE ON fuel_tax_proposals FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE TRIGGER fuel_tax_versions_immutable BEFORE UPDATE OR DELETE ON fuel_tax_versions FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
CREATE TRIGGER sale_tax_snapshots_immutable BEFORE UPDATE OR DELETE ON sale_tax_snapshots FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation();
REVOKE ALL ON FUNCTION valid_fuel_tax_rules(text,jsonb),calculate_fuel_tax(numeric,numeric,text,jsonb),validate_fuel_tax_version(),validate_sale_tax_snapshot(),capture_sale_tax_snapshot() FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION valid_fuel_tax_rules(text,jsonb),calculate_fuel_tax(numeric,numeric,text,jsonb) TO dlc_api_runtime;
REVOKE ALL ON TABLE fuel_tax_proposals,fuel_tax_versions,sale_tax_snapshots FROM PUBLIC,anon,authenticated,service_role;
ALTER TABLE fuel_tax_proposals ENABLE ROW LEVEL SECURITY;
ALTER TABLE fuel_tax_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_tax_snapshots ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT ON fuel_tax_proposals,fuel_tax_versions,sale_tax_snapshots TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON fuel_tax_proposals FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON fuel_tax_proposals FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_select ON fuel_tax_versions FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON fuel_tax_versions FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_select ON sale_tax_snapshots FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON sale_tax_snapshots FOR INSERT TO dlc_api_runtime WITH CHECK(true);
INSERT INTO permissions(code,description) VALUES('tax.policy.propose','Proponer política fiscal documentada'),('tax.policy.approve','Aprobar política fiscal de otra persona') ON CONFLICT(code) DO NOTHING;
