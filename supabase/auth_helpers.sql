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
-- fn_is_post_author: check if caller owns a post
-- ============================================================
-- Used by views to compute is_mine without exposing author_user_id.

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
