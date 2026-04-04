-- ============================================================
-- GirlTea App — Comments (single-level nesting)
-- ============================================================
-- Comment types: TEXT, IMAGE, or VOICE (3-minute cap on voice).
-- Text comments have body; image comments have media_url;
-- voice comments have media_url + duration.

CREATE TYPE comment_type AS ENUM (
    'TEXT',
    'IMAGE',
    'VOICE'
);

CREATE TABLE comments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id             UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author_user_id      UUID NOT NULL REFERENCES users(id),

    author_alias        TEXT NOT NULL,
    type                comment_type NOT NULL DEFAULT 'TEXT',

    body                TEXT,
    media_url           TEXT,
    duration_seconds    INT,

    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,

    CONSTRAINT chk_text_comment_has_body
        CHECK (type != 'TEXT' OR body IS NOT NULL),

    CONSTRAINT chk_media_comment_has_url
        CHECK (type = 'TEXT' OR media_url IS NOT NULL),

    CONSTRAINT chk_voice_comment_has_duration
        CHECK (type != 'VOICE' OR duration_seconds IS NOT NULL),

    CONSTRAINT chk_comment_duration_max_180s
        CHECK (duration_seconds IS NULL OR (duration_seconds > 0 AND duration_seconds <= 180)),

    CONSTRAINT chk_comment_deleted_consistency
        CHECK (
            (is_deleted = TRUE AND deleted_at IS NOT NULL)
            OR (is_deleted = FALSE AND deleted_at IS NULL)
        )
);
