-- Accrued operating expense is distinct from stock purchases and cash settlement.
CREATE TABLE expense_categories (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL REFERENCES organizations(id),
 code text NOT NULL CHECK(code~'^[A-Z0-9_]{2,30}$'),name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 100),
 class text NOT NULL CHECK(class IN('operating','capital','financial')),
 active boolean NOT NULL DEFAULT true,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,code),UNIQUE(id,organization_id)
);
CREATE TABLE expense_claims (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 category_id uuid NOT NULL,cost_center text NOT NULL CHECK(length(btrim(cost_center)) BETWEEN 2 AND 80),
 supplier_id uuid,invoice_reference text NOT NULL CHECK(length(btrim(invoice_reference)) BETWEEN 3 AND 120),
 amount_usd numeric(18,2) NOT NULL CHECK(amount_usd>0 AND amount_usd<1000000000),
 tax_usd numeric(18,2) CHECK(tax_usd>=0 AND tax_usd<=amount_usd),
 incurred_on date NOT NULL,due_on date,
 source_kind text NOT NULL CHECK(source_kind IN('other','maintenance','incident','purchase_fee')),
 source_id uuid,description text NOT NULL CHECK(length(btrim(description)) BETWEEN 10 AND 500),
 evidence_reference text NOT NULL CHECK(length(btrim(evidence_reference)) BETWEEN 3 AND 300),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(category_id,organization_id) REFERENCES expense_categories(id,organization_id),
 FOREIGN KEY(supplier_id,organization_id) REFERENCES suppliers(id,organization_id),
 FOREIGN KEY(created_by,organization_id) REFERENCES users(id,organization_id),
 CHECK((source_kind='other' AND source_id IS NULL) OR (source_kind<>'other' AND source_id IS NOT NULL)),
 UNIQUE(organization_id,command_id),UNIQUE(id,organization_id,branch_id)
);
CREATE UNIQUE INDEX expense_invoice_unique ON expense_claims(organization_id,coalesce(supplier_id,'00000000-0000-0000-0000-000000000000'::uuid),lower(btrim(invoice_reference)));
CREATE UNIQUE INDEX expense_source_once ON expense_claims(organization_id,source_kind,source_id) WHERE source_id IS NOT NULL;
CREATE INDEX expense_branch_date_idx ON expense_claims(branch_id,incurred_on DESC,id DESC);
CREATE FUNCTION validate_expense_claim() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c expense_categories%ROWTYPE;
BEGIN
 SELECT * INTO c FROM expense_categories WHERE id=NEW.category_id;
 IF c.id IS NULL OR NOT c.active OR c.organization_id<>NEW.organization_id
  THEN RAISE EXCEPTION 'Category unavailable' USING ERRCODE='23514'; END IF;
 IF (NEW.source_kind='maintenance' AND NOT EXISTS(SELECT 1 FROM maintenance_work_orders WHERE id=NEW.source_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id))
  OR (NEW.source_kind='incident' AND NOT EXISTS(SELECT 1 FROM incidents WHERE id=NEW.source_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id))
  OR (NEW.source_kind='purchase_fee' AND NOT EXISTS(SELECT 1 FROM purchase_orders WHERE id=NEW.source_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id))
 THEN RAISE EXCEPTION 'Linked source outside branch' USING ERRCODE='23514'; END IF;
 IF NEW.source_kind='purchase_fee' AND EXISTS(SELECT 1 FROM supplier_invoices i
  JOIN purchase_orders po ON po.id=i.purchase_order_id WHERE po.id=NEW.source_id AND i.supplier_id IS NOT DISTINCT FROM NEW.supplier_id
   AND lower(i.invoice_number)=lower(NEW.invoice_reference))
 THEN RAISE EXCEPTION 'Goods invoice cannot be booked again as operating expense' USING ERRCODE='23514'; END IF;
 IF NEW.incurred_on>(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date+1
  THEN RAISE EXCEPTION 'Future expense date invalid' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER expense_claim_guard BEFORE INSERT ON expense_claims FOR EACH ROW EXECUTE FUNCTION validate_expense_claim();
CREATE TABLE expense_decisions (
 expense_id uuid PRIMARY KEY,organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 outcome text NOT NULL CHECK(outcome IN('approved','rejected')),reason text NOT NULL CHECK(length(btrim(reason)) BETWEEN 10 AND 500),
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 decided_by uuid NOT NULL,decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(expense_id,organization_id,branch_id) REFERENCES expense_claims(id,organization_id,branch_id),
 FOREIGN KEY(decided_by,organization_id) REFERENCES users(id,organization_id),UNIQUE(organization_id,command_id)
);
CREATE FUNCTION validate_expense_decision() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE e expense_claims%ROWTYPE;
BEGIN
 SELECT * INTO e FROM expense_claims WHERE id=NEW.expense_id;
 IF e.id IS NULL OR e.organization_id<>NEW.organization_id OR e.branch_id<>NEW.branch_id OR e.created_by=NEW.decided_by
 THEN RAISE EXCEPTION 'Independent expense approval required' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER expense_decision_guard BEFORE INSERT ON expense_decisions FOR EACH ROW EXECUTE FUNCTION validate_expense_decision();
CREATE TABLE expense_disbursements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,branch_id uuid NOT NULL,
 expense_id uuid NOT NULL,amount_usd numeric(18,2) NOT NULL CHECK(amount_usd>0 AND amount_usd<1000000000),
 method text NOT NULL CHECK(method IN('cash','bank_reported')),cash_session_id uuid,evidence_reference text,
 command_id uuid NOT NULL,request_hash char(64) NOT NULL CHECK(request_hash~'^[0-9a-f]{64}$'),
 recorded_by uuid NOT NULL,recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),correlation_id uuid NOT NULL,
 FOREIGN KEY(expense_id,organization_id,branch_id) REFERENCES expense_claims(id,organization_id,branch_id),
 FOREIGN KEY(cash_session_id,organization_id,branch_id) REFERENCES cash_sessions(id,organization_id,branch_id),
 FOREIGN KEY(recorded_by,organization_id) REFERENCES users(id,organization_id),
 CHECK((method='cash' AND cash_session_id IS NOT NULL) OR (method='bank_reported' AND cash_session_id IS NULL)),
 CHECK(method='cash' OR length(btrim(evidence_reference)) BETWEEN 3 AND 200),
 UNIQUE(organization_id,command_id),UNIQUE(id,organization_id,branch_id)
);
ALTER TABLE cash_movements ADD COLUMN expense_disbursement_id uuid UNIQUE,
 ADD CONSTRAINT cash_expense_disbursement_fk FOREIGN KEY(expense_disbursement_id,organization_id,branch_id)
  REFERENCES expense_disbursements(id,organization_id,branch_id),
 ADD CONSTRAINT cash_expense_only_withdrawal CHECK(expense_disbursement_id IS NULL OR kind='withdrawal');
CREATE FUNCTION validate_expense_disbursement() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE e expense_claims%ROWTYPE; paid numeric;
BEGIN
 SELECT * INTO e FROM expense_claims WHERE id=NEW.expense_id FOR UPDATE;
 IF e.id IS NULL OR e.organization_id<>NEW.organization_id OR e.branch_id<>NEW.branch_id
  OR NOT EXISTS(SELECT 1 FROM expense_decisions WHERE expense_id=e.id AND outcome='approved')
 THEN RAISE EXCEPTION 'Expense is not approved' USING ERRCODE='23514'; END IF;
 SELECT coalesce(sum(amount_usd),0) INTO paid FROM expense_disbursements WHERE expense_id=e.id;
 IF NEW.amount_usd>e.amount_usd-paid THEN RAISE EXCEPTION 'Disbursement exceeds expense' USING ERRCODE='23514'; END IF;
 IF NEW.method='cash' THEN
  PERFORM lock_owned_open_cash(NEW.cash_session_id,NEW.recorded_by,NEW.organization_id,NEW.branch_id);
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER expense_disbursement_guard BEFORE INSERT ON expense_disbursements FOR EACH ROW EXECUTE FUNCTION validate_expense_disbursement();
CREATE FUNCTION post_expense_cash_withdrawal() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 IF NEW.method='cash' THEN
  INSERT INTO cash_movements(organization_id,branch_id,session_id,kind,delta_usd,reason,command_id,request_hash,created_by,correlation_id,expense_disbursement_id)
  VALUES(NEW.organization_id,NEW.branch_id,NEW.cash_session_id,'withdrawal',-NEW.amount_usd,
   'Gasto aprobado '||NEW.expense_id,gen_random_uuid(),NEW.request_hash,NEW.recorded_by,NEW.correlation_id,NEW.id);
 END IF;
 RETURN NULL;
END $$;
CREATE TRIGGER expense_cash_post AFTER INSERT ON expense_disbursements FOR EACH ROW EXECUTE FUNCTION post_expense_cash_withdrawal();
DO $$ DECLARE tab text; BEGIN
 FOREACH tab IN ARRAY ARRAY['expense_categories','expense_claims','expense_decisions','expense_disbursements'] LOOP
  EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY',tab);
  EXECUTE format('REVOKE ALL ON %I FROM PUBLIC,anon,authenticated,service_role',tab);
  EXECUTE format('GRANT SELECT,INSERT ON %I TO dlc_api_runtime',tab);
  EXECUTE format('CREATE POLICY dlc_api_select ON %I FOR SELECT TO dlc_api_runtime USING(true)',tab);
  EXECUTE format('CREATE POLICY dlc_api_insert ON %I FOR INSERT TO dlc_api_runtime WITH CHECK(true)',tab);
  EXECUTE format('CREATE TRIGGER expense_fact_immutable BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION prevent_inventory_movement_mutation()',tab);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION validate_expense_claim(),validate_expense_decision(),validate_expense_disbursement(),post_expense_cash_withdrawal()
 FROM PUBLIC,anon,authenticated,service_role;
