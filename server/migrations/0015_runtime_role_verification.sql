-- PostgreSQL 17 grants ADMIN, but not SET, to a role creator by default.
-- Allow the migration administrator to exercise the restricted role in tests.
-- Runtime privileges are not inherited by the migration connection.
GRANT dlc_api_runtime TO CURRENT_USER WITH SET TRUE, INHERIT FALSE;
