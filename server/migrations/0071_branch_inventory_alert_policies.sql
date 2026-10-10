-- Branch-scoped alert policy; one policy per branch with explicit defaults.
CREATE TABLE branch_inventory_alert_policies (
 branch_id uuid PRIMARY KEY,
 organization_id uuid NOT NULL,
 warning_percent numeric(5,2) NOT NULL DEFAULT 20.00 CHECK(warning_percent>0 AND warning_percent<100),
 critical_percent numeric(5,2) NOT NULL DEFAULT 10.00 CHECK(critical_percent>0 AND critical_percent<warning_percent),
 updated_by uuid,
 updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(updated_by,organization_id) REFERENCES users(id,organization_id)
);
ALTER TABLE branch_inventory_alert_policies ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE branch_inventory_alert_policies FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE ON TABLE branch_inventory_alert_policies TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON branch_inventory_alert_policies FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON branch_inventory_alert_policies FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_update ON branch_inventory_alert_policies FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
