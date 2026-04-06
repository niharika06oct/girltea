-- ============================================================
-- GirlTea App — Supabase Storage Bucket Setup
-- ============================================================
-- Run this once in the Supabase SQL Editor to create the
-- storage buckets. Supabase Storage is built on PostgreSQL
-- and uses the storage schema.

-- ---- Post media bucket ----
-- Stores images, videos, and voice recordings for posts.
-- File path convention: {postId}/{fileName}
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'post-media',
    'post-media',
    FALSE,
    104857600,  -- 100 MB (video max)
    ARRAY[
        'image/jpeg', 'image/png', 'image/webp', 'image/gif',
        'video/mp4', 'video/quicktime', 'video/webm',
        'audio/mpeg', 'audio/mp4', 'audio/m4a', 'audio/aac',
        'audio/ogg', 'audio/wav', 'audio/webm'
    ]
);

-- ---- Post thumbnails bucket ----
-- Auto-generated or client-uploaded video thumbnails.
-- File path convention: {postId}/{fileName}
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'post-thumbnails',
    'post-thumbnails',
    FALSE,
    2097152,  -- 2 MB
    ARRAY['image/jpeg', 'image/png', 'image/webp']
);

-- ---- Comment media bucket ----
-- Stores images and voice recordings for comments.
-- File path convention: {commentId}/{fileName}
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'comment-media',
    'comment-media',
    FALSE,
    10485760,  -- 10 MB
    ARRAY[
        'image/jpeg', 'image/png', 'image/webp', 'image/gif',
        'audio/mpeg', 'audio/mp4', 'audio/m4a', 'audio/aac',
        'audio/ogg', 'audio/wav', 'audio/webm'
    ]
);
