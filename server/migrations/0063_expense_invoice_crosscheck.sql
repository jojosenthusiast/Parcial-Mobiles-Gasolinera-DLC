-- A goods invoice cannot be entered again as a fee or unrelated operating expense.
-- Both directions are guarded, including invoices booked after an expense claim.
CREATE OR REPLACE FUNCTION validate_expense_claim() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE c expense_categories%ROWTYPE;
BEGIN
 SELECT * INTO c FROM expense_categories WHERE id=NEW.category_id;
 IF c.id IS NULL OR NOT c.active OR c.organization_id<>NEW.organization_id
  THEN RAISE EXCEPTION 'Category unavailable' USING ERRCODE='23514'; END IF;
 IF (NEW.source_kind='maintenance' AND NOT EXISTS(SELECT 1 FROM maintenance_work_orders WHERE id=NEW.source_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id))
  OR (NEW.source_kind='incident' AND NOT EXISTS(SELECT 1 FROM incidents WHERE id=NEW.source_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id))
  OR (NEW.source_kind='purchase_fee' AND NOT EXISTS(SELECT 1 FROM purchase_orders WHERE id=NEW.source_id AND organization_id=NEW.organization_id AND branch_id=NEW.branch_id))
 THEN RAISE EXCEPTION 'Linked source outside branch' USING ERRCODE='23514'; END IF;
 IF NEW.supplier_id IS NOT NULL THEN
  PERFORM pg_advisory_xact_lock(hashtextextended('supplier-invoice:'||NEW.organization_id||':'||NEW.supplier_id||':'||lower(btrim(NEW.invoice_reference)),0));
 END IF;
 IF NEW.supplier_id IS NOT NULL AND EXISTS(SELECT 1 FROM supplier_invoices i
  WHERE i.organization_id=NEW.organization_id AND i.supplier_id=NEW.supplier_id
   AND lower(btrim(i.invoice_number))=lower(btrim(NEW.invoice_reference)))
 THEN RAISE EXCEPTION 'Goods invoice cannot be booked as expense' USING ERRCODE='23514'; END IF;
 IF NEW.incurred_on>(clock_timestamp() AT TIME ZONE 'America/El_Salvador')::date+1
  THEN RAISE EXCEPTION 'Future expense date invalid' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;

CREATE FUNCTION guard_supplier_invoice_expense() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM pg_advisory_xact_lock(hashtextextended('supplier-invoice:'||NEW.organization_id||':'||NEW.supplier_id||':'||lower(btrim(NEW.invoice_number)),0));
 IF EXISTS(SELECT 1 FROM expense_claims e WHERE e.organization_id=NEW.organization_id
  AND e.supplier_id=NEW.supplier_id AND lower(btrim(e.invoice_reference))=lower(btrim(NEW.invoice_number)))
 THEN RAISE EXCEPTION 'Invoice already booked as expense' USING ERRCODE='23514'; END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER supplier_invoice_expense_crosscheck BEFORE INSERT ON supplier_invoices
 FOR EACH ROW EXECUTE FUNCTION guard_supplier_invoice_expense();
REVOKE ALL ON FUNCTION guard_supplier_invoice_expense() FROM PUBLIC,anon,authenticated,service_role;
