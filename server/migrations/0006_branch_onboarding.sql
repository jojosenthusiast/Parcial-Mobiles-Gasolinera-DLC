ALTER TABLE branches
  ADD COLUMN onboarding_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN onboarding_version integer NOT NULL DEFAULT 1 CHECK (onboarding_version > 0),
  ADD COLUMN configured_at timestamptz,
  ADD COLUMN activated_at timestamptz,
  ADD CONSTRAINT branches_onboarding_data_object CHECK (jsonb_typeof(onboarding_data) = 'object');

CREATE INDEX branches_onboarding_resume_idx
  ON branches (organization_id, status, updated_at DESC, id);
