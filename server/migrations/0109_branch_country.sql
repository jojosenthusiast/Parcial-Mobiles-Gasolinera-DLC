BEGIN;

-- Multi-country support: every branch belongs to one ISO 3166-1 alpha-2 country (uppercase).
-- Existing branches are El Salvador ('SV'); the default keeps legacy inserts valid.
-- Forward-only and idempotent: rollback is ALTER TABLE branches DROP COLUMN country_code (drops its CHECK and index).
ALTER TABLE branches ADD COLUMN IF NOT EXISTS country_code text NOT NULL DEFAULT 'SV'
 CONSTRAINT branches_country_code_format CHECK (country_code ~ '^[A-Z]{2}$');

CREATE INDEX IF NOT EXISTS branches_org_country_status_idx ON branches (organization_id, country_code, status);

COMMIT;
