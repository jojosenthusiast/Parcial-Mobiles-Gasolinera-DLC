-- Trusted DLC API role. Not a mobile/web role and not a Supabase Auth role.
-- A separate server LOGIN account must receive membership via a secure admin flow.
CREATE ROLE dlc_api_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
GRANT USAGE ON SCHEMA public TO dlc_api_runtime;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

GRANT SELECT ON TABLE public.organizations TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.organizations FOR SELECT TO dlc_api_runtime USING (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.branches TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.branches FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.branches FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.branches FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT ON TABLE public.schema_migrations TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.schema_migrations FOR SELECT TO dlc_api_runtime USING (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.idempotency_records TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.idempotency_records FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.idempotency_records FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.idempotency_records FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.outbox_events TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.outbox_events FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.outbox_events FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.outbox_events FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.background_jobs TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.background_jobs FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.background_jobs FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.background_jobs FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.employees TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.employees FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.employees FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.employees FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.users TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.users FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.users FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.users FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT ON TABLE public.roles TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.roles FOR SELECT TO dlc_api_runtime USING (true);

GRANT SELECT ON TABLE public.permissions TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.permissions FOR SELECT TO dlc_api_runtime USING (true);

GRANT SELECT ON TABLE public.role_permissions TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.role_permissions FOR SELECT TO dlc_api_runtime USING (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.user_role_assignments TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.user_role_assignments FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.user_role_assignments FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.user_role_assignments FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.auth_sessions TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.auth_sessions FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.auth_sessions FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.auth_sessions FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.auth_tokens TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.auth_tokens FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.auth_tokens FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.auth_tokens FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.auth_login_rate_limits TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.auth_login_rate_limits FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.auth_login_rate_limits FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.auth_login_rate_limits FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.account_action_tokens TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.account_action_tokens FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.account_action_tokens FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.account_action_tokens FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.audit_events TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.audit_events FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.audit_events FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT ON TABLE public.approval_policies TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.approval_policies FOR SELECT TO dlc_api_runtime USING (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.approval_requests TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.approval_requests FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.approval_requests FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.approval_requests FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.branch_operating_profiles TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.branch_operating_profiles FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.branch_operating_profiles FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.branch_operating_profiles FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.fuel_products TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.fuel_products FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.fuel_products FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.fuel_products FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.fuel_product_specifications TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.fuel_product_specifications FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.fuel_product_specifications FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.branch_fuel_offers TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.branch_fuel_offers FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.branch_fuel_offers FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.branch_fuel_offers FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.tanks TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.tanks FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.tanks FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.tanks FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.dispensers TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.dispensers FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.dispensers FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.dispensers FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.nozzles TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.nozzles FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.nozzles FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.nozzles FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.nozzle_tank_connections TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.nozzle_tank_connections FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.nozzle_tank_connections FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.nozzle_tank_connections FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.asset_blocks TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.asset_blocks FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.asset_blocks FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.asset_blocks FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.legacy_import_batches TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.legacy_import_batches FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.legacy_import_batches FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.legacy_import_rows TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.legacy_import_rows FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.legacy_import_rows FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.tank_inventory_balances TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.tank_inventory_balances FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.tank_inventory_balances FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.tank_inventory_balances FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.inventory_movements TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.inventory_movements FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.inventory_movements FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.fuel_market_references TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.fuel_market_references FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.fuel_market_references FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.fuel_price_proposals TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.fuel_price_proposals FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.fuel_price_proposals FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.fuel_price_proposals FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.fuel_price_versions TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.fuel_price_versions FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.fuel_price_versions FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.suppliers TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.suppliers FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.suppliers FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.suppliers FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.supplier_fuel_offers TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.supplier_fuel_offers FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.supplier_fuel_offers FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.supplier_fuel_offers FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.purchase_orders TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.purchase_orders FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.purchase_orders FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.purchase_orders FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.purchase_order_lines TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.purchase_order_lines FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.purchase_order_lines FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.purchase_order_lines FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.purchase_deliveries TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.purchase_deliveries FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.purchase_deliveries FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.purchase_deliveries FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.supplier_invoices TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.supplier_invoices FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.supplier_invoices FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.supplier_invoices FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.supplier_invoice_payments TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.supplier_invoice_payments FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.supplier_invoice_payments FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.purchase_approvals TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.purchase_approvals FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.purchase_approvals FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.nozzle_meter_states TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.nozzle_meter_states FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.nozzle_meter_states FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.nozzle_meter_states FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.nozzle_meter_readings TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.nozzle_meter_readings FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.nozzle_meter_readings FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT SELECT, INSERT, UPDATE ON TABLE public.dispense_authorizations TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.dispense_authorizations FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.dispense_authorizations FOR INSERT TO dlc_api_runtime WITH CHECK (true);
CREATE POLICY dlc_api_update ON public.dispense_authorizations FOR UPDATE TO dlc_api_runtime USING (true) WITH CHECK (true);

GRANT SELECT, INSERT ON TABLE public.dispense_authorization_events TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON public.dispense_authorization_events FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON public.dispense_authorization_events FOR INSERT TO dlc_api_runtime WITH CHECK (true);

GRANT USAGE ON SEQUENCE public.audit_events_id_seq, public.legacy_import_rows_id_seq TO dlc_api_runtime;
COMMENT ON ROLE dlc_api_runtime IS 'Trusted DLC backend only; user and tenant authorization enforced by the API. No direct client membership.';
