# Firebase Storage Architecture

## Overview

All media files (images, videos, voice recordings) are stored in **Firebase Cloud
Storage** (backed by Google Cloud Storage). The PostgreSQL database stores only the
URL reference (`media_url`, `thumbnail_url`), never the file itself.

## Bucket Structure

```
girltea-media/
├── posts/
│   └── {postId}/
│       ├── video.mp4              ← original video upload
│       ├── voice.m4a              ← voice recording
│       ├── image.jpg              ← image post
│       └── thumbnails/
│           └── thumb.jpg          ← auto-generated or client-uploaded
├── comments/
│   └── {commentId}/
│       ├── voice.m4a              ← voice comment
│       └── image.jpg              ← image comment
└── temp/
    └── {uid}/
        └── {uploadId}/
            └── raw-file.*         ← pending validation, auto-cleaned after 24h
```

## Upload Flow

```
┌─────────┐     1. Request upload URL     ┌──────────┐
│  Flutter │ ─────────────────────────────→│   API    │
│   App    │                               │  Server  │
│         │     2. Signed URL / postId     │          │
│         │ ←─────────────────────────────│          │
│         │                               └──────────┘
│         │     3. Upload file directly
│         │ ─────────────────────────────→┌──────────────────┐
│         │                               │ Firebase Storage │
│         │     4. Upload complete         │                  │
│         │ ←─────────────────────────────│                  │
└─────────┘                               └──────────────────┘
      │                                           │
      │     5. Confirm upload (postId, url)        │
      │ ─────────────────────────────→┌──────────┐│
      │                               │   API    ││  6. Cloud Function trigger
      │     7. Post created            │  Server  ││     validates file
      │ ←─────────────────────────────│          ││     (size, type, duration)
      │                               └──────────┘│
      │                                           │
```

### Step-by-step

1. **App** requests permission to upload (sends: group_id, media type, file size)
2. **API** verifies the user is an active member of the group, generates a post ID,
   returns the Storage path to upload to
3. **App** uploads the file directly to Firebase Storage using the Flutter
   `firebase_storage` SDK — the file never passes through your API server
4. **Storage** confirms upload complete
5. **App** calls API with the post ID and final download URL
6. **Cloud Function** (triggered on `finalize` event) validates:
   - File type matches allowed MIME types
   - File size within limits
   - For video/audio: extracts duration via FFprobe and rejects if > 180s
   - Generates thumbnail for video posts
7. **API** writes the post row to PostgreSQL with `media_url` pointing to the
   Storage object

## File Size Limits

| Content type | Max size | Enforced in |
|---|---|---|
| Image (post or comment) | 10 MB | Storage rules + API |
| Video (post only) | 100 MB | Storage rules + API |
| Voice (post or comment) | 10 MB | Storage rules + API |
| Thumbnail | 2 MB | Storage rules |

## Duration Validation

Firebase Storage rules **cannot** check media duration — they only see file size and
content type. Duration is validated in two places:

1. **Client-side** (Flutter): reject recordings > 180s before upload starts
2. **Server-side** (Cloud Function): on `finalize` trigger, use FFprobe to read
   duration from the uploaded file. If > 180s, delete the file and mark the post
   as rejected.

## Allowed MIME Types

### Posts

| Post type | Allowed MIME types |
|---|---|
| IMAGE | `image/jpeg`, `image/png`, `image/webp`, `image/gif` |
| VIDEO | `video/mp4`, `video/quicktime`, `video/webm` |
| VOICE | `audio/mpeg`, `audio/mp4`, `audio/m4a`, `audio/aac`, `audio/ogg`, `audio/wav`, `audio/webm` |

### Comments

| Comment type | Allowed MIME types |
|---|---|
| IMAGE | `image/jpeg`, `image/png`, `image/webp`, `image/gif` |
| VOICE | `audio/mpeg`, `audio/mp4`, `audio/m4a`, `audio/aac`, `audio/ogg`, `audio/wav`, `audio/webm` |

## Security Rules Summary

See `storage.rules` for the full rules. Key points:

- **All reads/writes require authentication** (`request.auth != null`)
- **File type checked on upload** via `request.resource.contentType`
- **File size checked on upload** via `request.resource.size`
- **Temp uploads** scoped to the user's own UID folder
- **Everything else denied** by default

## Image-Specific Considerations

Images are the simplest media type — no duration, no transcoding:

- **Formats**: JPEG, PNG, WebP, GIF (GIF for reactions/memes)
- **Storage**: Upload directly, no post-processing required for MVP
- **Future optimization**: Generate thumbnails / resize via Cloud Function on
  upload (e.g. 200px thumbnail for feed, full-res on tap). Libraries: `sharp`
  (Node.js) or `image_manipulation` (Firebase Extension)
- **EXIF stripping**: Important for privacy — EXIF data can contain GPS
  coordinates. Strip on upload via Cloud Function or client-side before upload

## Cost Optimization (for later)

| Strategy | When to apply |
|---|---|
| Transcode video to lower bitrate (720p, H.264) | When video uploads exceed ~1,000/day |
| Serve via Cloud CDN | When playback latency matters (India first) |
| Move old media to Coldline storage class | Posts older than 6 months with low views |
| Switch to Cloudflare R2 | When egress costs dominate (zero egress fees) |
| Generate multiple image sizes | When feed performance matters |
