CREATE TABLE employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  branch_id uuid REFERENCES branches(id),
  employee_code text NOT NULL,
  legal_name text NOT NULL CHECK (length(btrim(legal_name)) BETWEEN 1 AND 160),
  contact_email text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','leave','suspended','terminated')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, employee_code),
  UNIQUE (id, organization_id)
);

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  employee_id uuid,
  email_normalized text NOT NULL,
  display_name text NOT NULL CHECK (length(btrim(display_name)) BETWEEN 1 AND 160),
  password_hash text NOT NULL,
  status text NOT NULL DEFAULT 'invited' CHECK (status IN ('invited','active','suspended','locked')),
  must_change_password boolean NOT NULL DEFAULT true,
  permission_version integer NOT NULL DEFAULT 1 CHECK (permission_version > 0),
  failed_login_count integer NOT NULL DEFAULT 0 CHECK (failed_login_count >= 0),
  locked_until timestamptz,
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (email_normalized),
  UNIQUE (id, organization_id),
  FOREIGN KEY (employee_id, organization_id) REFERENCES employees(id, organization_id)
);

CREATE TABLE roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  name text NOT NULL,
  managed boolean NOT NULL DEFAULT false,
  UNIQUE (organization_id, code),
  UNIQUE (id, organization_id)
);

CREATE TABLE permissions (
  code text PRIMARY KEY,
  description text NOT NULL
);

INSERT INTO permissions (code, description) VALUES
 ('branch.read','Consultar sucursales permitidas'),
 ('branch.manage','Configurar sucursales'),
 ('branch.activate','Activar o suspender sucursales'),
 ('infrastructure.read','Consultar infraestructura de estación'),
 ('infrastructure.propose','Proponer cambios de infraestructura'),
 ('infrastructure.approve','Aprobar cambios de infraestructura'),
 ('fuel.read','Consultar catálogo de combustibles'),
 ('price.read','Consultar precios'),
 ('price.propose','Proponer precios'),
 ('price.approve','Aprobar precios'),
 ('price.apply','Aplicar precios aprobados'),
 ('inventory.read','Consultar inventario'),
 ('inventory.measure','Registrar mediciones'),
 ('inventory.receive','Recibir inventario'),
 ('inventory.adjust.request','Solicitar ajuste de inventario'),
 ('inventory.adjust.approve','Aprobar ajuste de inventario'),
 ('purchase.read','Consultar compras'),
 ('purchase.create','Crear compras'),
 ('purchase.approve','Aprobar compras'),
 ('purchase.receive','Recibir compras'),
 ('dispense.read','Consultar despacho'),
 ('dispense.authorize','Autorizar despacho'),
 ('sale.create','Registrar venta'),
 ('sale.read','Consultar ventas'),
 ('sale.refund.request','Solicitar reembolso'),
 ('sale.refund.approve','Aprobar reembolso'),
 ('cash.open','Abrir caja'),
 ('cash.count','Contar caja'),
 ('cash.close','Cerrar caja'),
 ('cut.read','Consultar cortes'),
 ('cut.capture','Capturar lecturas de corte'),
 ('cut.submit','Enviar corte a revisión'),
 ('cut.close','Cerrar corte'),
 ('cut.adjust.approve','Aprobar ajuste de corte'),
 ('incident.create','Registrar incidencia'),
 ('incident.read','Consultar incidencias'),
 ('incident.assign','Asignar incidencias'),
 ('incident.resolve','Resolver incidencias'),
 ('loss.approve','Aprobar pérdidas'),
 ('maintenance.plan','Planificar mantenimiento'),
 ('maintenance.work','Ejecutar mantenimiento'),
 ('maintenance.verify','Verificar mantenimiento'),
 ('maintenance.release','Liberar equipo'),
 ('staff.read','Consultar personal'),
 ('staff.manage','Gestionar personal'),
 ('user.manage','Gestionar cuentas y roles'),
 ('approval.decide','Resolver solicitudes de aprobación'),
 ('imports.preview','Preparar previsualización de una instalación legado'),
 ('imports.review','Revisar correspondencias y conflictos de importación'),
 ('expense.create','Registrar gastos'),
 ('expense.approve','Aprobar gastos'),
 ('expense.pay','Registrar pagos de gastos'),
 ('finance.cost.read','Consultar costos'),
 ('finance.margin.read','Consultar márgenes'),
 ('report.read','Consultar reportes'),
 ('report.export','Exportar reportes'),
 ('audit.read','Consultar auditoría'),
 ('integration.manage','Configurar integraciones')
ON CONFLICT (code) DO NOTHING;

CREATE TABLE role_permissions (
  organization_id uuid NOT NULL REFERENCES organizations(id),
  role_id uuid NOT NULL,
  permission_code text NOT NULL REFERENCES permissions(code),
  PRIMARY KEY (role_id, permission_code),
  FOREIGN KEY (role_id, organization_id) REFERENCES roles(id, organization_id)
);

CREATE TABLE user_role_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  user_id uuid NOT NULL,
  role_id uuid NOT NULL,
  branch_id uuid,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  assigned_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (valid_until IS NULL OR valid_until > valid_from),
  FOREIGN KEY (user_id, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (role_id, organization_id) REFERENCES roles(id, organization_id),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (assigned_by, organization_id) REFERENCES users(id, organization_id)
);
CREATE INDEX user_role_current_idx ON user_role_assignments(user_id, branch_id, valid_from, valid_until);

CREATE TABLE auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  user_id uuid NOT NULL,
  permission_version integer NOT NULL,
  device_label text,
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  revoke_reason text,
  FOREIGN KEY (user_id, organization_id) REFERENCES users(id, organization_id)
);
CREATE INDEX auth_sessions_user_idx ON auth_sessions(user_id, expires_at) WHERE revoked_at IS NULL;

CREATE TABLE auth_tokens (
  token_hash bytea PRIMARY KEY,
  session_id uuid NOT NULL REFERENCES auth_sessions(id) ON DELETE CASCADE,
  token_type text NOT NULL CHECK (token_type IN ('access','refresh')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);
CREATE INDEX auth_tokens_session_idx ON auth_tokens(session_id, token_type, expires_at);

CREATE TABLE auth_login_rate_limits (
  fingerprint_hash bytea PRIMARY KEY,
  window_started_at timestamptz NOT NULL,
  attempt_count integer NOT NULL CHECK (attempt_count > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX auth_login_rate_limits_updated_idx ON auth_login_rate_limits(updated_at);

CREATE TABLE account_action_tokens (
  token_hash bytea PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id),
  token_type text NOT NULL CHECK (token_type IN ('invite','password_reset')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz
);
CREATE INDEX account_action_tokens_user_idx ON account_action_tokens(user_id, token_type, expires_at);

CREATE TABLE audit_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id uuid NOT NULL REFERENCES organizations(id),
  branch_id uuid,
  actor_user_id uuid,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  correlation_id uuid NOT NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  before_data jsonb,
  after_data jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (actor_user_id, organization_id) REFERENCES users(id, organization_id),
  CHECK (jsonb_typeof(metadata) = 'object')
);
CREATE INDEX audit_events_entity_idx ON audit_events(organization_id, entity_type, entity_id, occurred_at DESC);
CREATE INDEX audit_events_actor_idx ON audit_events(organization_id, actor_user_id, occurred_at DESC);

CREATE FUNCTION prevent_audit_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'audit_events is append-only' USING ERRCODE = '55000';
END;
$$;
CREATE TRIGGER audit_events_immutable BEFORE UPDATE OR DELETE ON audit_events
FOR EACH ROW EXECUTE FUNCTION prevent_audit_mutation();

CREATE TABLE approval_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  action text NOT NULL,
  branch_id uuid,
  enabled boolean NOT NULL DEFAULT true,
  require_different_approver boolean NOT NULL DEFAULT true,
  amount_threshold numeric(18,2),
  currency char(3) NOT NULL DEFAULT 'USD' CHECK (currency = 'USD'),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  CHECK (amount_threshold IS NULL OR amount_threshold >= 0),
  UNIQUE NULLS NOT DISTINCT (organization_id, action, branch_id)
);

CREATE TABLE approval_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  branch_id uuid,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  requested_by uuid NOT NULL,
  decided_by uuid,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
  payload jsonb NOT NULL,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  FOREIGN KEY (branch_id, organization_id) REFERENCES branches(id, organization_id),
  FOREIGN KEY (requested_by, organization_id) REFERENCES users(id, organization_id),
  FOREIGN KEY (decided_by, organization_id) REFERENCES users(id, organization_id),
  CHECK (decided_by IS NULL OR decided_by <> requested_by)
);
CREATE INDEX approval_pending_idx ON approval_requests(organization_id, branch_id, created_at) WHERE status = 'pending';
