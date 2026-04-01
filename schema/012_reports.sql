-- ============================================================
-- GirlTea App — Reports (moderation)
-- ============================================================

CREATE TABLE reports (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type         report_target_type NOT NULL,
    target_id           UUID NOT NULL,

    reporter_user_id    UUID NOT NULL REFERENCES users(id),
    reason              TEXT NOT NULL,

    resolved            BOOLEAN NOT NULL DEFAULT FALSE,
    resolved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
