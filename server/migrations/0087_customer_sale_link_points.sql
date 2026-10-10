BEGIN;

CREATE TABLE customer_sale_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  branch_id uuid NOT NULL,
  sale_id uuid NOT NULL,
  customer_id uuid NOT NULL,
  command_id uuid NOT NULL,
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  linked_by uuid NOT NULL,
  linked_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (sale_id, organization_id, branch_id) REFERENCES sales(id, organization_id, branch_id),
  FOREIGN KEY (customer_id, organization_id) REFERENCES customer_accounts(id, organization_id),
  FOREIGN KEY (linked_by, organization_id) REFERENCES users(id, organization_id),
  UNIQUE (organization_id, command_id),
  UNIQUE (sale_id),
  UNIQUE (id, organization_id, branch_id)
);
CREATE INDEX customer_sale_links_customer_idx ON customer_sale_links (organization_id, customer_id, linked_at DESC);

CREATE FUNCTION validate_customer_sale_link() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('sale-collection:'||NEW.sale_id::text,0));
  IF NOT EXISTS (
    SELECT 1 FROM sales s JOIN customer_accounts c
      ON c.id=NEW.customer_id AND c.organization_id=NEW.organization_id AND c.status='active'
    JOIN sale_collection_balances b ON b.id=s.id AND b.organization_id=s.organization_id AND b.branch_id=s.branch_id
    WHERE s.id=NEW.sale_id AND s.organization_id=NEW.organization_id AND s.branch_id=NEW.branch_id
      AND b.collection_status='pending_collection'
  ) THEN
    RAISE EXCEPTION 'Active customer and pending sale required' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER customer_sale_link_guard BEFORE INSERT ON customer_sale_links
  FOR EACH ROW EXECUTE FUNCTION validate_customer_sale_link();
CREATE FUNCTION reject_customer_sale_link_mutation() RETURNS trigger
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'Customer-sale links are immutable; correct them with an audited reversal' USING ERRCODE='55000';
END; $$;
CREATE TRIGGER customer_sale_link_immutable BEFORE UPDATE OR DELETE ON customer_sale_links
  FOR EACH ROW EXECUTE FUNCTION reject_customer_sale_link_mutation();
ALTER TABLE customer_sale_links ENABLE ROW LEVEL SECURITY;
CREATE POLICY dlc_api_select ON customer_sale_links FOR SELECT TO dlc_api_runtime USING (true);
CREATE POLICY dlc_api_insert ON customer_sale_links FOR INSERT TO dlc_api_runtime WITH CHECK (true);
REVOKE ALL ON TABLE customer_sale_links FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT, INSERT ON TABLE customer_sale_links TO dlc_api_runtime;
REVOKE ALL ON FUNCTION validate_customer_sale_link() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION reject_customer_sale_link_mutation() FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION award_points_for_paid_customer_sale() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE sale_row record; program_row customer_loyalty_programs%ROWTYPE; eligible numeric; points bigint;
BEGIN
  IF NEW.outcome <> 'confirmed' THEN RETURN NEW; END IF;
  SELECT s.id, s.organization_id, s.total_usd, l.customer_id, b.collection_status
    INTO sale_row
    FROM payment_attempts a
    JOIN sales s ON s.id=a.sale_id AND s.organization_id=a.organization_id AND s.branch_id=a.branch_id
    JOIN sale_collection_balances b ON b.id=s.id AND b.organization_id=s.organization_id AND b.branch_id=s.branch_id
    JOIN customer_sale_links l ON l.sale_id=s.id AND l.organization_id=s.organization_id AND l.branch_id=s.branch_id
    JOIN customer_accounts ca ON ca.id=l.customer_id AND ca.organization_id=s.organization_id AND ca.status='active'
   WHERE a.id=NEW.attempt_id AND a.organization_id=NEW.organization_id AND a.branch_id=NEW.branch_id;
  IF sale_row.id IS NULL OR sale_row.collection_status <> 'paid' THEN RETURN NEW; END IF;
  SELECT * INTO program_row FROM customer_loyalty_programs
   WHERE organization_id=NEW.organization_id AND status='active' ORDER BY version DESC LIMIT 1;
  IF program_row.id IS NULL THEN RETURN NEW; END IF;
  eligible := sale_row.total_usd;
  IF eligible < program_row.minimum_eligible_usd THEN RETURN NEW; END IF;
  points := floor(eligible * program_row.points_per_eligible_usd)::bigint;
  IF points <= 0 THEN RETURN NEW; END IF;
  INSERT INTO customer_points_ledger (
    organization_id, customer_id, program_id, event_type, points_delta,
    source_type, source_id, command_id, reason, expires_at, created_by
  ) VALUES (
    NEW.organization_id, sale_row.customer_id, program_row.id, 'earn', points,
    'sale', sale_row.id, NEW.command_id, 'Puntos por venta pagada',
    CASE WHEN program_row.points_expire_after_days IS NULL THEN NULL
      ELSE now() + (program_row.points_expire_after_days::text || ' days')::interval END,
    NEW.created_by
  ) ON CONFLICT (organization_id, source_type, source_id, event_type) DO NOTHING;
  RETURN NEW;
END; $$;
CREATE TRIGGER customer_sale_points_award AFTER INSERT ON payment_events
  FOR EACH ROW EXECUTE FUNCTION award_points_for_paid_customer_sale();
REVOKE ALL ON FUNCTION award_points_for_paid_customer_sale() FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
