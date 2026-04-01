-- ============================================================
-- GirlTea App — Group Invites (WhatsApp / link gating)
-- ============================================================

CREATE TABLE group_invites (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id            UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,

    token_hash          TEXT NOT NULL UNIQUE,

    created_by_user_id  UUID NOT NULL REFERENCES users(id),

    expires_at          TIMESTAMPTZ,
    max_uses            INT,
    use_count           INT NOT NULL DEFAULT 0,

    revoked_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_use_count_non_negative
        CHECK (use_count >= 0),

    CONSTRAINT chk_max_uses_positive
        CHECK (max_uses IS NULL OR max_uses > 0)
);
