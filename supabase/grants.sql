-- ============================================================
-- GirlTea App — Baseline role grants
-- ============================================================
-- Hosted Supabase auto-grants table privileges to `anon` and
-- `authenticated` via ALTER DEFAULT PRIVILEGES. When applying the
-- raw schema to a plain/local Postgres those defaults don't fire,
-- so RLS policies exist but the coarse table privilege is missing
-- and every query fails with "permission denied for table ...".
--
-- This file restores that baseline. Row-level access is still
-- gated by the RLS policies in rls_policies.sql; these grants only
-- open the table-level privilege that RLS then narrows.
--
-- Apply order: schema tables → THIS FILE → rls_policies.sql
-- (rls_policies.sql REVOKEs SELECT on posts/comments/
-- group_memberships afterwards so those stay view-only.)

GRANT USAGE ON SCHEMA public TO anon, authenticated;

GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA public
    TO authenticated;

GRANT SELECT
    ON ALL TABLES IN SCHEMA public
    TO anon;

GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA public
    TO anon, authenticated;

-- Keep future objects working without re-running this file.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO anon, authenticated;
