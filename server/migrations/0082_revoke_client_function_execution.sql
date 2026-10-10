-- PostgreSQL grants EXECUTE on new functions to PUBLIC by default. Restrict both
-- existing and future application functions to the explicitly granted server roles.
REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA public
  FROM PUBLIC, anon, authenticated, service_role;

-- Remove PostgreSQL's global PUBLIC default as schema-specific REVOKE cannot
-- cancel a privilege granted globally. Also remove any role-specific defaults.
ALTER DEFAULT PRIVILEGES
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;

-- Supabase projects commonly create future public objects as postgres. Keep
-- that owner protected even if the migration runner uses another role.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
  REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, anon, authenticated, service_role;
