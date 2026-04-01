-- ============================================================
-- GirlTea App — Comments (single-level nesting)
-- ============================================================

CREATE TABLE comments (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id             UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author_user_id      UUID NOT NULL REFERENCES users(id),

    author_alias        TEXT NOT NULL,
    body                TEXT NOT NULL,

    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,

    CONSTRAINT chk_comment_deleted_consistency
        CHECK (
            (is_deleted = TRUE AND deleted_at IS NOT NULL)
            OR (is_deleted = FALSE AND deleted_at IS NULL)
        )
);
