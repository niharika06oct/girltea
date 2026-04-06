# Supabase Storage Architecture

## Overview

All media files (images, videos, voice recordings) are stored in **Supabase Storage**
(backed by S3-compatible object storage). The PostgreSQL database stores only the URL
reference (`media_url`, `thumbnail_url`), never the file itself.

Supabase Storage is free (1 GB storage, 2 GB bandwidth/month) with no credit card
required.

## Buckets

| Bucket | Contents | Max file size | Allowed types |
|---|---|---|---|
| `post-media` | Images, videos, voice for posts | 100 MB | JPEG, PNG, WebP, GIF, MP4, QuickTime, WebM, MP3, M4A, AAC, OGG, WAV |
| `post-thumbnails` | Video thumbnail previews | 2 MB | JPEG, PNG, WebP |
| `comment-media` | Images, voice for comments | 10 MB | JPEG, PNG, WebP, GIF, MP3, M4A, AAC, OGG, WAV |

All buckets are **private** (not publicly accessible). Authenticated users access
files through Supabase client SDK, which handles signed URLs automatically.

## File Path Convention

```
post-media/
└── {postId}/
    ├── video.mp4
    ├── voice.m4a
    └── image.jpg

post-thumbnails/
└── {postId}/
    └── thumb.jpg

comment-media/
└── {commentId}/
    ├── voice.m4a
    └── image.jpg
```

## Upload Flow

```
┌─────────┐                               ┌──────────────────┐
│  Flutter │  1. Upload file via SDK        │    Supabase      │
│   App    │ ─────────────────────────────→│    Storage       │
│          │                               │                  │
│          │  2. Returns file path/URL      │  (S3-compatible) │
│          │ ←─────────────────────────────│                  │
└─────────┘                               └──────────────────┘
      │
      │  3. Create post/comment with media_url
      │ ─────────────────────────────→┌──────────────────┐
      │                               │    Supabase      │
      │  4. Row created                │    PostgreSQL    │
      │ ←─────────────────────────────│                  │
      │                               └──────────────────┘
```

### Step-by-step

1. **App** uploads the file directly to Supabase Storage using the Flutter
   `supabase_flutter` SDK. The SDK handles auth tokens automatically.
2. **Supabase** validates: file size, MIME type (bucket-level), and RLS policy
   (user must be authenticated). Returns the file path.
3. **App** creates the post/comment row in PostgreSQL via Supabase client or
   API, setting `media_url` to the storage path.
4. **PostgreSQL** enforces schema constraints (duration, content type match, etc.)

### Reading files

```dart
// Get a signed URL (valid for 1 hour) for a private file
final url = await supabase.storage
    .from('post-media')
    .createSignedUrl('postId/video.mp4', 3600);

// Or use getPublicUrl() if bucket is set to public later
```

## Security

Security is handled by **PostgreSQL Row Level Security (RLS)** policies on the
`storage.objects` table — see `storage_policies.sql`.

Current policies:
- **Upload**: Any authenticated user can upload
- **Read**: Any authenticated user can read (group membership check at API layer)
- **Delete**: Any authenticated user can delete (ownership check at API layer)

### Tightening policies later

For stricter access control, you can check group membership in the RLS policy
itself by joining against `group_memberships`. Example:

```sql
CREATE POLICY "Only group members can read post media"
ON storage.objects FOR SELECT
TO authenticated
USING (
    bucket_id = 'post-media'
    AND EXISTS (
        SELECT 1 FROM posts p
        JOIN group_memberships gm ON gm.group_id = p.group_id
        WHERE p.id = (storage.foldername(name))[1]::uuid
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);
```

This is optional for MVP — the API layer already checks membership before
serving content.

## Duration Validation

Supabase Storage **cannot** check media duration — it only validates file size
and MIME type. Duration is validated in two places:

1. **Client-side** (Flutter): Stop recording at 180s, check before upload
2. **Server-side** (Supabase Edge Function or API): After upload, read duration
   from file metadata. If > 180s, delete the file and reject the post.

## Image Considerations

- **Formats**: JPEG, PNG, WebP, GIF
- **No duration check** needed — just file size (10 MB max)
- **EXIF stripping**: Important for privacy (GPS coordinates). Strip client-side
  before upload, or via a Supabase Edge Function on upload
- **Future optimization**: Generate thumbnails via Supabase Image Transformation
  (built-in, Blaze plan) or Edge Function with `sharp`

## Supabase Free Tier Limits

| Resource | Free limit |
|---|---|
| Storage | 1 GB |
| Bandwidth | 2 GB/month |
| File uploads | Unlimited |
| Max file size | 50 MB default (we set per-bucket) |

For MVP and early testing, this is sufficient. If you outgrow the free tier,
Supabase Pro is $25/month with 100 GB storage and 250 GB bandwidth.

## Setup Instructions

### 1. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) and sign up (free, no credit card)
2. Click "New Project"
3. Name: `girltea`
4. Region: Choose the closest to India (e.g. `ap-south-1` Mumbai or `ap-southeast-1` Singapore)
5. Set a database password (save it somewhere safe)
6. Click "Create new project" — wait ~2 minutes

### 2. Create storage buckets

1. Go to the **SQL Editor** in the Supabase dashboard
2. Paste the contents of `storage_buckets.sql` and run it
3. Verify: Go to **Storage** in the sidebar — you should see three buckets

### 3. Apply RLS policies

1. In the **SQL Editor**, paste the contents of `storage_policies.sql` and run it
2. Verify: Go to **Storage** → click a bucket → **Policies** tab

### 4. Get your project credentials

In **Settings** → **API**, copy:
- **Project URL**: `https://xxxxx.supabase.co`
- **Anon public key**: `eyJhb...` (safe to embed in client)
- **Service role key**: `eyJhb...` (server-side only, never in client)

You'll use these when setting up the Flutter app with `supabase_flutter`.
