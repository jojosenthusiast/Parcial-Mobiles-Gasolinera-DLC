-- Global product metadata requires an organization-wide permission distinct from branch pricing.
INSERT INTO permissions(code,description) VALUES
 ('pos.catalog.global.manage','Administrar datos maestros de producto para toda la organización')
ON CONFLICT(code) DO NOTHING;
CREATE INDEX branch_assortment_active_idx ON branch_assortments(branch_id,catalog_product_id) WHERE active;
