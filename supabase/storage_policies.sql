-- ============================================================
-- GirlTea App — Supabase Storage RLS Policies
-- ============================================================
-- File paths use {postId}/file.mp4 or {commentId}/file.mp4 —
-- NO user IDs in paths. This is critical: media_url is returned
-- by the feed views, so any identifier in the path is visible
-- to all group members.
--
-- Read access is gated on group membership: the first path
-- segment is the postId or commentId, which maps to a group.
-- fn_is_group_member() checks the calling user's membership.
--
-- Run auth_helpers.sql BEFORE this file.

-- ============================================================
-- Helper: resolve group_id from a post-media storage path
-- ============================================================
-- (storage.foldername(name))[1] returns the first path segment
-- which is the postId by convention.

CREATE OR REPLACE FUNCTION fn_storage_post_group(p_object_name TEXT)
RETURNS UUID AS $$
DECLARE
    v_post_id UUID;
    v_group_id UUID;
BEGIN
    BEGIN
        v_post_id := (storage.foldername(p_object_name))[1]::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;

    SELECT group_id INTO v_group_id
    FROM posts WHERE id = v_post_id;

    RETURN v_group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, storage;


-- ============================================================
-- Helper: resolve group_id from a comment-media storage path
-- ============================================================

CREATE OR REPLACE FUNCTION fn_storage_comment_group(p_object_name TEXT)
RETURNS UUID AS $$
DECLARE
    v_comment_id UUID;
    v_group_id UUID;
BEGIN
    BEGIN
        v_comment_id := (storage.foldername(p_object_name))[1]::UUID;
    EXCEPTION WHEN OTHERS THEN
        RETURN NULL;
    END;

    SELECT p.group_id INTO v_group_id
    FROM comments c
    JOIN posts p ON p.id = c.post_id
    WHERE c.id = v_comment_id;

    RETURN v_group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, storage;


-- ============================================================
-- POST MEDIA BUCKET
-- ============================================================

CREATE POLICY "Group members can upload post media"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'post-media'
    AND fn_is_group_member(fn_storage_post_group(name))
);

CREATE POLICY "Group members can read post media"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'post-media'
    AND fn_is_group_member(fn_storage_post_group(name))
);

CREATE POLICY "Post authors can delete their post media"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'post-media'
    AND fn_is_post_author((storage.foldername(name))[1]::UUID)
);

-- ============================================================
-- POST THUMBNAILS BUCKET
-- ============================================================

CREATE POLICY "Group members can upload post thumbnails"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'post-thumbnails'
    AND fn_is_group_member(fn_storage_post_group(name))
);

CREATE POLICY "Group members can read post thumbnails"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'post-thumbnails'
    AND fn_is_group_member(fn_storage_post_group(name))
);

CREATE POLICY "Post authors can delete post thumbnails"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'post-thumbnails'
    AND fn_is_post_author((storage.foldername(name))[1]::UUID)
);

-- ============================================================
-- COMMENT MEDIA BUCKET
-- ============================================================

CREATE POLICY "Group members can upload comment media"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'comment-media'
    AND fn_is_group_member(fn_storage_comment_group(name))
);

CREATE POLICY "Group members can read comment media"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'comment-media'
    AND fn_is_group_member(fn_storage_comment_group(name))
);

CREATE POLICY "Comment authors can delete comment media"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'comment-media'
    AND fn_is_comment_author((storage.foldername(name))[1]::UUID)
);
