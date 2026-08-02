-- ============================================================
-- GirlTea App — Auth Helper Functions
-- ============================================================
-- SECURITY DEFINER helpers that bypass RLS to avoid infinite
-- recursion when RLS policies on group_memberships need to
-- check group_memberships. Called from RLS policies and views.
--
-- All functions lock search_path to prevent escalation.

-- ============================================================
-- fn_is_group_member: core membership check
-- ============================================================
-- Returns TRUE if auth.uid() is an ACTIVE member of the given group.
-- Used by nearly every RLS policy. SECURITY DEFINER so it reads
-- group_memberships without triggering RLS on that table.

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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_post_group: resolve group_id from a post_id
-- ============================================================
-- CRITICAL: RLS policies on comments and post_upvotes need to
-- check membership in the post's group. But SELECT on posts is
-- revoked from authenticated. Without this DEFINER helper,
-- every comment insert and upvote insert throws
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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_is_group_owner: check if caller has OWNER role
-- ============================================================
-- Used by group update and entry question policies instead of
-- created_by_user_id (which never changes, contradicting the
-- democratic model).

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
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
