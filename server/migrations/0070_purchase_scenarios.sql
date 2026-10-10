CREATE TABLE purchase_scenarios (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 fuel_product_id uuid NOT NULL,tank_id uuid NOT NULL,quote_id uuid NOT NULL,
 quantity_l numeric(24,3) NOT NULL CHECK(quantity_l>0),
 snapshot jsonb NOT NULL CHECK(jsonb_typeof(snapshot)='object'),
 valid_until timestamptz NOT NULL,command_id uuid NOT NULL,
 request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(tank_id,branch_id,fuel_product_id) REFERENCES tanks(id,branch_id,fuel_product_id),
 FOREIGN KEY(quote_id,organization_id) REFERENCES supplier_fuel_quotes(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,command_id),UNIQUE(id,organization_id,branch_id)
);
CREATE FUNCTION guard_purchase_scenario() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE quote supplier_fuel_quotes%ROWTYPE;tank tanks%ROWTYPE;balance tank_inventory_balances%ROWTYPE;
BEGIN
 SELECT * INTO quote FROM supplier_fuel_quotes WHERE id=NEW.quote_id;
 SELECT * INTO tank FROM tanks WHERE id=NEW.tank_id;
 SELECT * INTO balance FROM tank_inventory_balances WHERE tank_id=NEW.tank_id;
 IF quote.id IS NULL OR quote.organization_id<>NEW.organization_id OR quote.fuel_product_id<>NEW.fuel_product_id
  OR quote.confidence<>'confirmed' OR quote.valid_from>clock_timestamp() OR quote.valid_until<=clock_timestamp()
  OR NEW.valid_until>quote.valid_until OR tank.status<>'active' OR balance.tank_id IS NULL
  OR NEW.quantity_l>tank.safe_fill_limit_l-balance.on_hand_l OR NEW.quantity_l<quote.minimum_delivery_l
 THEN RAISE EXCEPTION 'Scenario quote or tank capacity unavailable' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER purchase_scenario_guard BEFORE INSERT ON purchase_scenarios FOR EACH ROW EXECUTE FUNCTION guard_purchase_scenario();
CREATE TABLE purchase_scenario_approvals (
 scenario_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 outcome text NOT NULL CHECK(outcome IN('approved','rejected')),
 reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 approved_by uuid NOT NULL,approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(scenario_id,organization_id,branch_id) REFERENCES purchase_scenarios(id,organization_id,branch_id),
 FOREIGN KEY(approved_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id)
);
CREATE FUNCTION guard_purchase_scenario_approval() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM purchase_scenarios s WHERE s.id=NEW.scenario_id
  AND s.organization_id=NEW.organization_id AND s.branch_id=NEW.branch_id AND s.created_by<>NEW.approved_by
  AND s.valid_until>clock_timestamp())
 THEN RAISE EXCEPTION 'Independent current scenario approval required' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER scenario_approval_guard BEFORE INSERT ON purchase_scenario_approvals FOR EACH ROW EXECUTE FUNCTION guard_purchase_scenario_approval();
CREATE TABLE purchase_scenario_orders (
 scenario_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 order_id uuid NOT NULL UNIQUE,linked_by uuid NOT NULL,linked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(scenario_id,organization_id,branch_id) REFERENCES purchase_scenarios(id,organization_id,branch_id),
 FOREIGN KEY(order_id,organization_id,branch_id) REFERENCES purchase_orders(id,organization_id,branch_id),
 FOREIGN KEY(linked_by,organization_id) REFERENCES users(id,organization_id)
);
CREATE FUNCTION guard_scenario_order_link() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE s purchase_scenarios%ROWTYPE;q supplier_fuel_quotes%ROWTYPE;
BEGIN
 SELECT * INTO s FROM purchase_scenarios WHERE id=NEW.scenario_id;
 SELECT * INTO q FROM supplier_fuel_quotes WHERE id=s.quote_id;
 IF s.id IS NULL OR s.organization_id<>NEW.organization_id OR s.branch_id<>NEW.branch_id
  OR NOT EXISTS(SELECT 1 FROM purchase_scenario_approvals a WHERE a.scenario_id=s.id AND a.outcome='approved')
  OR NOT EXISTS(SELECT 1 FROM purchase_orders po JOIN purchase_order_lines l ON l.purchase_order_id=po.id
   WHERE po.id=NEW.order_id AND po.organization_id=NEW.organization_id AND po.branch_id=NEW.branch_id
   AND po.supplier_id=q.supplier_id AND po.status='draft' AND po.created_by=NEW.linked_by
   AND l.fuel_product_id=s.fuel_product_id AND l.tank_id=s.tank_id
   AND l.quantity_ordered=round(s.quantity_l/CASE WHEN q.unit='us_gallon' THEN 3.785411784 ELSE 1 END,3)
   AND l.unit=q.unit AND l.agreed_unit_price_usd=q.unit_price_usd)
 THEN RAISE EXCEPTION 'Order does not match approved scenario' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER scenario_order_guard BEFORE INSERT ON purchase_scenario_orders
 FOR EACH ROW EXECUTE FUNCTION guard_scenario_order_link();
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['purchase_scenarios','purchase_scenario_approvals','purchase_scenario_orders'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',tab);
  EXECUTE format('GRANT SELECT,INSERT ON %I TO dlc_api_runtime',tab);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',tab);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',tab);
  EXECUTE format('CREATE TRIGGER scenario_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',tab);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION guard_purchase_scenario(),guard_purchase_scenario_approval(),guard_scenario_order_link()
 FROM PUBLIC,anon,authenticated,service_role;
INSERT INTO permissions(code,description) VALUES('purchase.scenario.approve','Aprobar escenario de abastecimiento') ON CONFLICT(code) DO NOTHING;
