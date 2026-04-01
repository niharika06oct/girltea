-- ============================================================
-- GirlTea App — Posts (rants, stories, etc.)
-- ============================================================

CREATE TYPE post_type AS ENUM (
    'TEXT',
    'IMAGE',
    'AUDIO'
);

CREATE TABLE posts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id            UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    author_user_id      UUID NOT NULL REFERENCES users(id),

    author_alias        TEXT NOT NULL,
    type                post_type NOT NULL DEFAULT 'TEXT',
    body                TEXT,
    media_url           TEXT,

    upvote_count        INT NOT NULL DEFAULT 0,

    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,

    CONSTRAINT chk_post_has_content
        CHECK (body IS NOT NULL OR media_url IS NOT NULL),

    CONSTRAINT chk_post_deleted_consistency
        CHECK (
            (is_deleted = TRUE AND deleted_at IS NOT NULL)
            OR (is_deleted = FALSE AND deleted_at IS NULL)
        )
);
