-- ============================================================
-- GirlTea App — Supabase Storage RLS Policies
-- ============================================================
-- Supabase uses PostgreSQL Row Level Security (RLS) on the
-- storage.objects table. These policies control who can
-- upload, read, and delete media files.
--
-- auth.uid() returns the authenticated user's ID.
-- (storage.foldername(name))[1] returns the first path segment
-- (the postId or commentId).

-- ============================================================
-- POST MEDIA BUCKET
-- ============================================================

-- Authenticated users can upload to post-media
CREATE POLICY "Authenticated users can upload post media"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'post-media'
);

-- Authenticated users can view post media
CREATE POLICY "Authenticated users can read post media"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'post-media'
);

-- Users can delete their own post media
-- (first folder segment is postId — app layer verifies ownership)
CREATE POLICY "Authenticated users can delete post media"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'post-media'
);

-- ============================================================
-- POST THUMBNAILS BUCKET
-- ============================================================

CREATE POLICY "Authenticated users can upload post thumbnails"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'post-thumbnails'
);

CREATE POLICY "Authenticated users can read post thumbnails"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'post-thumbnails'
);

CREATE POLICY "Authenticated users can delete post thumbnails"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'post-thumbnails'
);

-- ============================================================
-- COMMENT MEDIA BUCKET
-- ============================================================

CREATE POLICY "Authenticated users can upload comment media"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
    bucket_id = 'comment-media'
);

CREATE POLICY "Authenticated users can read comment media"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'comment-media'
);

CREATE POLICY "Authenticated users can delete comment media"
ON storage.objects FOR DELETE
TO authenticated
USING (
    bucket_id = 'comment-media'
);
