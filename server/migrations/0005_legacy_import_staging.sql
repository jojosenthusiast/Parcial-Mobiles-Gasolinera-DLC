CREATE TABLE legacy_import_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  source_installation_id uuid NOT NULL,
  source_sha256 char(64) NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
  source_bytes bigint NOT NULL CHECK (source_bytes > 0 AND source_bytes <= 33554432),
  schema_version integer NOT NULL CHECK (schema_version = 1),
  status text NOT NULL CHECK (status IN ('preview','review_required','blocked')),
  cutover_at timestamptz,
  manifest jsonb NOT NULL,
  preview jsonb NOT NULL,
  raw_snapshot jsonb NOT NULL,
  initiated_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (initiated_by, organization_id) REFERENCES users(id, organization_id),
  UNIQUE (organization_id, source_installation_id, source_sha256)
);
CREATE INDEX legacy_import_batches_org_idx ON legacy_import_batches(organization_id, created_at DESC);

CREATE TABLE legacy_import_rows (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  batch_id uuid NOT NULL REFERENCES legacy_import_batches(id) ON DELETE CASCADE,
  collection_name text NOT NULL,
  row_index integer NOT NULL CHECK (row_index >= 0),
  legacy_id text,
  proposed_id uuid,
  quality text NOT NULL CHECK (quality IN ('confirmed','provisional','estimatedLegacy','missing','stale','disputed')),
  issue_codes text[] NOT NULL DEFAULT '{}',
  raw_record jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (batch_id, collection_name, row_index)
);
CREATE INDEX legacy_import_rows_batch_idx ON legacy_import_rows(batch_id, collection_name, row_index);
