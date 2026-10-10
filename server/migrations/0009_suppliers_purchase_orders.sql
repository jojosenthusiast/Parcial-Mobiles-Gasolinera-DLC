CREATE TABLE suppliers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  legal_name text NOT NULL CHECK (length(btrim(legal_name)) BETWEEN 1 AND 180),
  display_name text,
  tax_id_normalized text,
  contact_name text,
  contact_email text,
  contact_phone text,
  payment_terms_days integer NOT NULL DEFAULT 0 CHECK (payment_terms_days BETWEEN 0 AND 365),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','blocked','inactive')),
  notes text,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (created_by, organization_id) REFERENCES users(id, organization_id),
  UNIQUE (id, organization_id)
);
INSERT INTO permissions(code,description) VALUES
 ('supplier.invoice.manage','Registrar y consultar facturas de proveedores'),
 ('supplier.payment.record','Registrar pagos externos a proveedores')
ON CONFLICT(code) DO NOTHING;
CREATE UNIQUE INDEX suppliers_tax_id_unique ON suppliers(organization_id,tax_id_normalized) WHERE tax_id_normalized IS NOT NULL;
CREATE INDEX suppliers_search_idx ON suppliers(organization_id,status,lower(legal_name));

CREATE TABLE supplier_fuel_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  supplier_product_code text,
  last_quoted_unit_price_usd numeric(18,8) CHECK (last_quoted_unit_price_usd IS NULL OR last_quoted_unit_price_usd > 0),
  last_quoted_unit text CHECK (last_quoted_unit IS NULL OR last_quoted_unit IN ('liter','us_gallon')),
  quote_valid_until date,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (supplier_id,organization_id) REFERENCES suppliers(id,organization_id),
  FOREIGN KEY (fuel_product_id,organization_id) REFERENCES fuel_products(id,organization_id),
  UNIQUE (supplier_id,fuel_product_id),
  UNIQUE (id,organization_id)
);

CREATE TABLE purchase_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  order_number text NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','pending_approval','approved','ordered','partially_received','received','rejected','cancelled')),
  currency char(3) NOT NULL DEFAULT 'USD' CHECK (currency='USD'),
  requested_delivery_at timestamptz,
  notes text,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid NOT NULL,
  approved_by uuid,
  approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id,organization_id) REFERENCES branches(id,organization_id),
  FOREIGN KEY (supplier_id,organization_id) REFERENCES suppliers(id,organization_id),
  FOREIGN KEY (created_by,organization_id) REFERENCES users(id,organization_id),
  FOREIGN KEY (approved_by,organization_id) REFERENCES users(id,organization_id),
  CHECK (approved_by IS NULL OR approved_by <> created_by),
  CHECK ((status IN ('draft','pending_approval','rejected') AND approved_by IS NULL)
      OR (status IN ('approved','ordered','partially_received','received') AND approved_by IS NOT NULL)
      OR status='cancelled'),
  UNIQUE (id,organization_id),
  UNIQUE (id,organization_id,branch_id),
  UNIQUE (id,organization_id,supplier_id),
  UNIQUE (organization_id,order_number)
);
CREATE INDEX purchase_orders_branch_status_idx ON purchase_orders(organization_id,branch_id,status,created_at DESC);

CREATE TABLE purchase_order_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  purchase_order_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  quantity_ordered numeric(24,12) NOT NULL CHECK (quantity_ordered > 0),
  unit text NOT NULL CHECK (unit IN ('liter','us_gallon')),
  agreed_unit_price_usd numeric(18,8) NOT NULL CHECK (agreed_unit_price_usd > 0),
  received_quantity numeric(24,12) NOT NULL DEFAULT 0 CHECK (received_quantity >= 0 AND received_quantity <= quantity_ordered),
  tank_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (purchase_order_id,organization_id,branch_id) REFERENCES purchase_orders(id,organization_id,branch_id),
  FOREIGN KEY (fuel_product_id,organization_id) REFERENCES fuel_products(id,organization_id),
  FOREIGN KEY (tank_id,branch_id,fuel_product_id) REFERENCES tanks(id,branch_id,fuel_product_id),
  UNIQUE (id,organization_id),
  UNIQUE (id,organization_id,purchase_order_id,branch_id,fuel_product_id),
  UNIQUE (purchase_order_id,fuel_product_id)
);
CREATE INDEX purchase_order_lines_order_idx ON purchase_order_lines(purchase_order_id);

CREATE UNIQUE INDEX inventory_movement_tenant_identity_idx ON inventory_movements(id,organization_id,branch_id);
CREATE TABLE purchase_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  purchase_order_id uuid NOT NULL,
  purchase_order_line_id uuid NOT NULL,
  fuel_product_id uuid NOT NULL,
  tank_id uuid NOT NULL,
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  status text NOT NULL DEFAULT 'processing' CHECK (status IN ('processing','received')),
  accepted_quantity numeric(24,12) NOT NULL CHECK (accepted_quantity > 0),
  unit text NOT NULL CHECK (unit IN ('liter','us_gallon')),
  billed_quantity numeric(24,12) CHECK (billed_quantity IS NULL OR billed_quantity >= 0),
  supplier_delivery_reference text NOT NULL CHECK (length(btrim(supplier_delivery_reference)) BETWEEN 1 AND 120),
  compartment_reference text,
  document_reference text NOT NULL CHECK (length(btrim(document_reference)) BETWEEN 1 AND 120),
  inventory_movement_id uuid UNIQUE,
  actor_user_id uuid NOT NULL,
  received_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (purchase_order_id,organization_id,branch_id) REFERENCES purchase_orders(id,organization_id,branch_id),
  FOREIGN KEY (purchase_order_line_id,organization_id,purchase_order_id,branch_id,fuel_product_id) REFERENCES purchase_order_lines(id,organization_id,purchase_order_id,branch_id,fuel_product_id),
  FOREIGN KEY (tank_id,branch_id,fuel_product_id) REFERENCES tanks(id,branch_id,fuel_product_id),
  FOREIGN KEY (inventory_movement_id,organization_id,branch_id) REFERENCES inventory_movements(id,organization_id,branch_id),
  FOREIGN KEY (actor_user_id,organization_id) REFERENCES users(id,organization_id),
  UNIQUE (organization_id,command_id)
);
CREATE INDEX purchase_deliveries_order_idx ON purchase_deliveries(purchase_order_id,created_at DESC);

CREATE TABLE supplier_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  purchase_order_id uuid NOT NULL,
  supplier_id uuid NOT NULL,
  invoice_number text NOT NULL,
  currency char(3) NOT NULL DEFAULT 'USD' CHECK (currency='USD'),
  subtotal_usd numeric(18,2) NOT NULL CHECK (subtotal_usd >= 0),
  tax_usd numeric(18,2) NOT NULL DEFAULT 0 CHECK (tax_usd >= 0),
  total_usd numeric(18,2) NOT NULL CHECK (total_usd > 0 AND total_usd = subtotal_usd + tax_usd),
  due_at date,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','partially_paid','paid','disputed','void')),
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (purchase_order_id,organization_id,supplier_id) REFERENCES purchase_orders(id,organization_id,supplier_id),
  FOREIGN KEY (supplier_id,organization_id) REFERENCES suppliers(id,organization_id),
  FOREIGN KEY (created_by,organization_id) REFERENCES users(id,organization_id),
  UNIQUE (organization_id,supplier_id,invoice_number),
  UNIQUE (id,organization_id)
);

CREATE TABLE supplier_invoice_payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  amount_usd numeric(18,2) NOT NULL CHECK (amount_usd > 0),
  paid_at timestamptz NOT NULL,
  payment_method text NOT NULL CHECK (payment_method IN ('bank_transfer','check','cash','other')),
  external_reference text,
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  recorded_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (invoice_id,organization_id) REFERENCES supplier_invoices(id,organization_id),
  FOREIGN KEY (recorded_by,organization_id) REFERENCES users(id,organization_id),
  UNIQUE (organization_id,external_reference) DEFERRABLE INITIALLY IMMEDIATE,
  UNIQUE (organization_id,command_id)
);

CREATE TABLE purchase_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  purchase_order_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('approved','rejected')),
  reason text,
  decided_by uuid NOT NULL,
  decided_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (purchase_order_id,organization_id) REFERENCES purchase_orders(id,organization_id),
  FOREIGN KEY (decided_by,organization_id) REFERENCES users(id,organization_id),
  UNIQUE (purchase_order_id)
);
