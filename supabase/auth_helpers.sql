-- ============================================================
-- GirlTea App — Auth Helper Functions
-- ============================================================
-- SECURITY DEFINER helpers that bypass RLS to avoid infinite
-- recursion when RLS policies on group_memberships need to
-- check group_memberships. Called from RLS policies and views.
--
-- All functions: SECURITY DEFINER, locked search_path, STABLE.
-- STABLE lets Postgres cache the result per-statement so a
-- 500-row feed doesn't run 500 separate membership checks.

-- ============================================================
-- fn_is_group_member: core membership check
-- ============================================================

CREATE OR REPLACE FUNCTION fn_is_group_member(p_group_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM group_memberships
        WHERE group_id = p_group_id
          AND user_id = auth.uid()
          AND status = 'ACTIVE'
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_post_group: resolve group_id from a post_id
-- ============================================================
-- Required because SELECT on posts is revoked from authenticated.
-- Without this, comment/upvote INSERT policies fail with
-- "permission denied for table posts".

CREATE OR REPLACE FUNCTION fn_post_group(p_post_id UUID)
RETURNS UUID AS $$
DECLARE
    v_group_id UUID;
BEGIN
    SELECT group_id INTO v_group_id
    FROM posts
    WHERE id = p_post_id
      AND is_deleted = FALSE;

    RETURN v_group_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_is_post_author: check if caller owns a post
-- ============================================================

CREATE OR REPLACE FUNCTION fn_is_post_author(p_post_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM posts
        WHERE id = p_post_id
          AND author_user_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_is_comment_author: check if caller owns a comment
-- ============================================================

CREATE OR REPLACE FUNCTION fn_is_comment_author(p_comment_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM comments
        WHERE id = p_comment_id
          AND author_user_id = auth.uid()
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_is_group_owner: check if caller has OWNER role
-- ============================================================

CREATE OR REPLACE FUNCTION fn_is_group_owner(p_group_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM group_memberships
        WHERE group_id = p_group_id
          AND user_id = auth.uid()
          AND role = 'OWNER'
          AND status = 'ACTIVE'
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;


-- ============================================================
-- Revoke EXECUTE from anon on all helpers
-- ============================================================
-- Defence in depth: all functions check auth.uid() IS NULL,
-- but anon should never call them in the first place.

REVOKE EXECUTE ON FUNCTION fn_is_group_member(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_post_group(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_is_post_author(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_is_comment_author(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_is_group_owner(UUID) FROM anon;
