CREATE TABLE saved_report_filters (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),organization_id uuid NOT NULL,
 branch_id uuid NOT NULL,user_id uuid NOT NULL,
 name text NOT NULL CHECK(length(btrim(name)) BETWEEN 2 AND 80),
 report_type text NOT NULL CHECK(report_type IN('closed_cuts','fuel_sales','tank_movements','incidents','purchase_orders')),
 filters jsonb NOT NULL CHECK(jsonb_typeof(filters)='object'),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(),updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(branch_id,organization_id) REFERENCES branches(id,organization_id),
 FOREIGN KEY(user_id,organization_id) REFERENCES users(id,organization_id),
 UNIQUE(organization_id,user_id,branch_id,name)
);
CREATE INDEX saved_report_filters_owner_idx ON saved_report_filters(organization_id,user_id,branch_id,updated_at DESC);
ALTER TABLE saved_report_filters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE saved_report_filters FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT,INSERT,UPDATE,DELETE ON TABLE saved_report_filters TO dlc_api_runtime;
CREATE POLICY dlc_api_select ON saved_report_filters FOR SELECT TO dlc_api_runtime USING(true);
CREATE POLICY dlc_api_insert ON saved_report_filters FOR INSERT TO dlc_api_runtime WITH CHECK(true);
CREATE POLICY dlc_api_update ON saved_report_filters FOR UPDATE TO dlc_api_runtime USING(true) WITH CHECK(true);
CREATE POLICY dlc_api_delete ON saved_report_filters FOR DELETE TO dlc_api_runtime USING(true);
