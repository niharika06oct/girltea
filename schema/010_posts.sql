-- ============================================================
-- GirlTea App — Posts (rants, stories, etc.)
-- ============================================================
-- Post types: TEXT, IMAGE, VIDEO, VOICE
-- VIDEO and VOICE are capped at 180 seconds (3 minutes).
-- Each media post is standalone — no mixing media types in
-- a single post.

CREATE TYPE post_type AS ENUM (
    'TEXT',
    'IMAGE',
    'VIDEO',
    'VOICE'
);

CREATE TABLE posts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id            UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    author_user_id      UUID NOT NULL REFERENCES users(id),

    author_alias        TEXT NOT NULL,
    type                post_type NOT NULL DEFAULT 'TEXT',

    body                TEXT,
    media_url           TEXT,
    duration_seconds    INT,
    thumbnail_url       TEXT,

    upvote_count        INT NOT NULL DEFAULT 0,

    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,

    CONSTRAINT chk_text_post_has_body
        CHECK (type != 'TEXT' OR body IS NOT NULL),

    CONSTRAINT chk_media_post_has_url
        CHECK (type = 'TEXT' OR media_url IS NOT NULL),

    CONSTRAINT chk_timed_media_has_duration
        CHECK (type NOT IN ('VIDEO', 'VOICE') OR duration_seconds IS NOT NULL),

    CONSTRAINT chk_duration_max_180s
        CHECK (duration_seconds IS NULL OR (duration_seconds > 0 AND duration_seconds <= 180)),

    CONSTRAINT chk_post_deleted_consistency
        CHECK (
            (is_deleted = TRUE AND deleted_at IS NOT NULL)
            OR (is_deleted = FALSE AND deleted_at IS NULL)
        )
);
