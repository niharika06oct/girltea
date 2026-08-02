-- ============================================================
-- GirlTea App — Supabase Auth Integration
-- ============================================================
-- Links the app's users table to Supabase's auth.users.
-- users.id = auth.users.id (same UUID).
--
-- Profile creation happens at onboarding (after first OTP login),
-- NOT automatically on signup, because required fields (display_name,
-- date_of_birth) don't exist at auth time.
--
-- Run this in the Supabase SQL Editor after creating all app tables.

-- ============================================================
-- Foreign key: users.id → auth.users.id
-- ============================================================
-- This ensures every app profile is backed by a Supabase auth account.

ALTER TABLE users
ADD CONSTRAINT fk_users_auth
FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;

-- ============================================================
-- Helper function: check if current user has completed onboarding
-- ============================================================
-- Can be called from the app or used in RLS policies.

CREATE OR REPLACE FUNCTION fn_has_profile()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM users
        WHERE id = auth.uid()
          AND is_deleted = FALSE
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================================
-- Helper function: get current user's profile
-- ============================================================

CREATE OR REPLACE FUNCTION fn_my_profile()
RETURNS SETOF users AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM users
    WHERE id = auth.uid()
      AND is_deleted = FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
