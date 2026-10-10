-- OPTIONAL, admin only (Supabase SQL editor, role postgres). One transaction, safe to re-run.
-- Run AFTER qa-migration-0110.sql. Removes the never-opened QA cuts that use the old 14:00-06:00 evening window so that
-- `node scripts/seed-qa-operations.mjs` can create today's correct pair (morning 06:00-14:00, evening 14:00-22:00).
-- Scope: organization 00000000-0000-4000-8000-0000000000a1, branches QA-SV-01 and QA-GT-01 only.
-- Per branch it finds the first operating day whose evening window is not 8 hours long and, only if every cut from that
-- day on is still 'scheduled' (never opened: no meter, tank or asset data), deletes those cuts and then the cut profiles
-- no cut references any more. Branches with an opened, prepared or closed cut in that range are left untouched (a notice
-- says so); for them the seeder keeps the legacy cuts and creates the correct pair from the next day.
-- The profile immutability trigger is disabled and re-enabled inside this transaction.
BEGIN;
SET LOCAL lock_timeout = '15s';
SELECT pg_advisory_xact_lock(hashtext('dlc-schema-migrations'));

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE version = '0110_cut_evening_window.sql') THEN
    RAISE EXCEPTION 'Apply qa-migration-0110.sql first.';
  END IF;
END $$;

ALTER TABLE operational_cut_profiles DISABLE TRIGGER operational_cut_profiles_immutable;

DO $$
DECLARE
  org constant uuid := '00000000-0000-4000-8000-0000000000a1';
  b record;
  first_legacy date;
  removed integer;
  total_removed integer := 0;
  total_profiles integer := 0;
  dropped integer;
BEGIN
  FOR b IN SELECT id, code FROM branches WHERE organization_id = org AND code IN ('QA-SV-01', 'QA-GT-01') ORDER BY code LOOP
    SELECT min(c.operational_date) INTO first_legacy FROM operational_cuts c
     WHERE c.organization_id = org AND c.branch_id = b.id AND c.slot = 2 AND c.ends_at - c.starts_at <> interval '8 hours';
    IF first_legacy IS NULL THEN RAISE NOTICE '% has no legacy cuts', b.code; CONTINUE; END IF;
    IF EXISTS (SELECT 1 FROM operational_cuts c WHERE c.organization_id = org AND c.branch_id = b.id
                AND c.operational_date >= first_legacy AND c.status <> 'scheduled') THEN
      RAISE NOTICE '% kept: a cut from % on is already opened/closed', b.code, first_legacy; CONTINUE;
    END IF;
    BEGIN
      DELETE FROM operational_cuts c WHERE c.organization_id = org AND c.branch_id = b.id AND c.operational_date >= first_legacy;
      GET DIAGNOSTICS removed = ROW_COUNT;
      DELETE FROM operational_cut_profiles p WHERE p.organization_id = org AND p.branch_id = b.id
         AND NOT EXISTS (SELECT 1 FROM operational_cuts c WHERE c.profile_id = p.id);
      GET DIAGNOSTICS dropped = ROW_COUNT;
      total_removed := total_removed + removed; total_profiles := total_profiles + dropped;
      RAISE NOTICE '% : removed % scheduled cuts from % and % unused profiles', b.code, removed, first_legacy, dropped;
    EXCEPTION WHEN foreign_key_violation THEN
      RAISE NOTICE '% kept: cuts from % are referenced by other records', b.code, first_legacy;
    END;
  END LOOP;
  RAISE NOTICE 'total: % cuts, % profiles removed', total_removed, total_profiles;
END $$;

ALTER TABLE operational_cut_profiles ENABLE TRIGGER operational_cut_profiles_immutable;

SELECT b.code, c.operational_date, c.slot, c.status, c.starts_at, c.ends_at
  FROM operational_cuts c JOIN branches b ON b.id = c.branch_id
 WHERE c.organization_id = '00000000-0000-4000-8000-0000000000a1' ORDER BY b.code, c.operational_date, c.slot;
COMMIT;
