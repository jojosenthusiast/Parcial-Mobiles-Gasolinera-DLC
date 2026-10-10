-- Backend-only persistence: custom API authentication is not Supabase Auth.
-- Clients must use the DLC API; no anon/authenticated/service_role grants.
-- RLS intentionally denies Data API access. The trusted database owner runs the API.

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.organizations FROM PUBLIC;
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.branches FROM PUBLIC;
ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.schema_migrations FROM PUBLIC;
ALTER TABLE public.idempotency_records ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.idempotency_records FROM PUBLIC;
ALTER TABLE public.outbox_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.outbox_events FROM PUBLIC;
ALTER TABLE public.background_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.background_jobs FROM PUBLIC;
ALTER TABLE public.employees ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.employees FROM PUBLIC;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.users FROM PUBLIC;
ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.roles FROM PUBLIC;
ALTER TABLE public.permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.permissions FROM PUBLIC;
ALTER TABLE public.role_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.role_permissions FROM PUBLIC;
ALTER TABLE public.user_role_assignments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.user_role_assignments FROM PUBLIC;
ALTER TABLE public.auth_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.auth_sessions FROM PUBLIC;
ALTER TABLE public.auth_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.auth_tokens FROM PUBLIC;
ALTER TABLE public.auth_login_rate_limits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.auth_login_rate_limits FROM PUBLIC;
ALTER TABLE public.account_action_tokens ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.account_action_tokens FROM PUBLIC;
ALTER TABLE public.audit_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.audit_events FROM PUBLIC;
ALTER TABLE public.approval_policies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.approval_policies FROM PUBLIC;
ALTER TABLE public.approval_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.approval_requests FROM PUBLIC;
ALTER TABLE public.branch_operating_profiles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.branch_operating_profiles FROM PUBLIC;
ALTER TABLE public.fuel_products ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.fuel_products FROM PUBLIC;
ALTER TABLE public.fuel_product_specifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.fuel_product_specifications FROM PUBLIC;
ALTER TABLE public.branch_fuel_offers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.branch_fuel_offers FROM PUBLIC;
ALTER TABLE public.tanks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.tanks FROM PUBLIC;
ALTER TABLE public.dispensers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.dispensers FROM PUBLIC;
ALTER TABLE public.nozzles ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nozzles FROM PUBLIC;
ALTER TABLE public.nozzle_tank_connections ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nozzle_tank_connections FROM PUBLIC;
ALTER TABLE public.asset_blocks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.asset_blocks FROM PUBLIC;
ALTER TABLE public.legacy_import_batches ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.legacy_import_batches FROM PUBLIC;
ALTER TABLE public.legacy_import_rows ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.legacy_import_rows FROM PUBLIC;
ALTER TABLE public.tank_inventory_balances ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.tank_inventory_balances FROM PUBLIC;
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.inventory_movements FROM PUBLIC;
ALTER TABLE public.fuel_market_references ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.fuel_market_references FROM PUBLIC;
ALTER TABLE public.fuel_price_proposals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.fuel_price_proposals FROM PUBLIC;
ALTER TABLE public.fuel_price_versions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.fuel_price_versions FROM PUBLIC;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.suppliers FROM PUBLIC;
ALTER TABLE public.supplier_fuel_offers ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.supplier_fuel_offers FROM PUBLIC;
ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.purchase_orders FROM PUBLIC;
ALTER TABLE public.purchase_order_lines ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.purchase_order_lines FROM PUBLIC;
ALTER TABLE public.purchase_deliveries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.purchase_deliveries FROM PUBLIC;
ALTER TABLE public.supplier_invoices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.supplier_invoices FROM PUBLIC;
ALTER TABLE public.supplier_invoice_payments ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.supplier_invoice_payments FROM PUBLIC;
ALTER TABLE public.purchase_approvals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.purchase_approvals FROM PUBLIC;
ALTER TABLE public.nozzle_meter_states ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nozzle_meter_states FROM PUBLIC;
ALTER TABLE public.nozzle_meter_readings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nozzle_meter_readings FROM PUBLIC;
ALTER TABLE public.dispense_authorizations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.dispense_authorizations FROM PUBLIC;
ALTER TABLE public.dispense_authorization_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.dispense_authorization_events FROM PUBLIC;

DO $security$
DECLARE client_role text; table_name text; sequence_name text;
BEGIN
  FOREACH client_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname=client_role) THEN
      FOREACH table_name IN ARRAY ARRAY['organizations','branches','schema_migrations','idempotency_records','outbox_events','background_jobs','employees','users','roles','permissions','role_permissions','user_role_assignments','auth_sessions','auth_tokens','auth_login_rate_limits','account_action_tokens','audit_events','approval_policies','approval_requests','branch_operating_profiles','fuel_products','fuel_product_specifications','branch_fuel_offers','tanks','dispensers','nozzles','nozzle_tank_connections','asset_blocks','legacy_import_batches','legacy_import_rows','tank_inventory_balances','inventory_movements','fuel_market_references','fuel_price_proposals','fuel_price_versions','suppliers','supplier_fuel_offers','purchase_orders','purchase_order_lines','purchase_deliveries','supplier_invoices','supplier_invoice_payments','purchase_approvals','nozzle_meter_states','nozzle_meter_readings','dispense_authorizations','dispense_authorization_events'] LOOP
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM %I', table_name, client_role);
      END LOOP;
      FOR sequence_name IN SELECT pg_get_serial_sequence('public.' || t, 'id') FROM unnest(ARRAY['audit_events','legacy_import_rows']) t LOOP
        IF sequence_name IS NOT NULL THEN
          EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM %I', sequence_name, client_role);
        END IF;
      END LOOP;
    END IF;
  END LOOP;
END;
$security$;

ALTER FUNCTION public.prevent_audit_mutation() SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.prevent_audit_mutation() FROM PUBLIC;
ALTER FUNCTION public.prevent_inventory_movement_mutation() SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.prevent_inventory_movement_mutation() FROM PUBLIC;
ALTER FUNCTION public.prevent_fuel_price_version_mutation() SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.prevent_fuel_price_version_mutation() FROM PUBLIC;
ALTER FUNCTION public.prevent_nozzle_meter_reading_mutation() SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.prevent_nozzle_meter_reading_mutation() FROM PUBLIC;
ALTER FUNCTION public.prevent_dispense_event_mutation() SET search_path = public, pg_temp;
REVOKE ALL ON FUNCTION public.prevent_dispense_event_mutation() FROM PUBLIC;
