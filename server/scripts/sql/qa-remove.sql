-- DLC QA tenant HARD removal (admin only; destructive and irreversible).
-- Deletes organization 00000000-0000-4000-8000-0000000000a1 and every row that references it,
-- including its audit trail (append-only trigger is disabled and re-enabled inside this transaction).
-- Does NOT touch migration 0109, other tenants, or global rows (permissions, schema_migrations).
-- Soft alternative (keeps history):  UPDATE users SET status='suspended', permission_version=permission_version+1
--   WHERE organization_id='00000000-0000-4000-8000-0000000000a1';  UPDATE branches SET status='archived' WHERE organization_id='00000000-0000-4000-8000-0000000000a1';
-- If the DO block reports leftover tables, the tenant has operational data (sales, ledgers, ...); use the soft path.
BEGIN;
SET LOCAL lock_timeout = '15s';
ALTER TABLE audit_events DISABLE TRIGGER audit_events_immutable;

DO $$
DECLARE
  org constant uuid := '00000000-0000-4000-8000-0000000000a1';
  rel record;
  pass int := 0;
  progress boolean;
  affected bigint;
  org_gone boolean := false;
  leftovers text := '';
BEGIN
  -- tables keyed by user, not organization
  DELETE FROM account_action_tokens WHERE user_id IN (SELECT id FROM users WHERE organization_id = org);
  LOOP
    pass := pass + 1;
    progress := false;
    FOR rel IN
      SELECT c.table_name FROM information_schema.columns c
        JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name AND t.table_type = 'BASE TABLE'
       WHERE c.table_schema = 'public' AND c.column_name = 'organization_id' AND c.table_name <> 'organizations'
    LOOP
      BEGIN
        EXECUTE format('DELETE FROM public.%I WHERE organization_id = $1', rel.table_name) USING org;
        GET DIAGNOSTICS affected = ROW_COUNT;
        IF affected > 0 THEN progress := true; END IF;
      EXCEPTION WHEN foreign_key_violation THEN NULL; -- a child table is deleted in a later pass
      END;
    END LOOP;
    BEGIN
      DELETE FROM organizations WHERE id = org;
      org_gone := true;
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    EXIT WHEN org_gone OR (NOT progress) OR pass >= 25;
  END LOOP;
  IF NOT org_gone THEN
    FOR rel IN
      SELECT c.table_name FROM information_schema.columns c
       WHERE c.table_schema = 'public' AND c.column_name = 'organization_id' AND c.table_name <> 'organizations'
    LOOP
      EXECUTE format('SELECT count(*) FROM public.%I WHERE organization_id = $1', rel.table_name) INTO affected USING org;
      IF affected > 0 THEN leftovers := leftovers || rel.table_name || '(' || affected || ') '; END IF;
    END LOOP;
    RAISE EXCEPTION 'QA tenant still referenced by: %', leftovers;
  END IF;
END $$;

ALTER TABLE audit_events ENABLE TRIGGER audit_events_immutable;
SELECT (SELECT count(*) FROM organizations WHERE id = '00000000-0000-4000-8000-0000000000a1') AS organizations_left;
COMMIT;
