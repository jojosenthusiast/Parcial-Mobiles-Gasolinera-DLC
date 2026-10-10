ALTER TABLE incidents ADD COLUMN command_id uuid NOT NULL DEFAULT gen_random_uuid(),
 ADD COLUMN request_hash char(64) NOT NULL DEFAULT repeat('0',64) CHECK(request_hash~'^[0-9a-f]{64}$');
ALTER TABLE incidents ALTER COLUMN command_id DROP DEFAULT,ALTER COLUMN request_hash DROP DEFAULT;
CREATE UNIQUE INDEX incidents_command_idx ON incidents(organization_id,command_id);
