-- ============================================================
-- GirlTea App — Group Removal Requests
-- ============================================================
-- Democratic removal: any member can raise a request to remove
-- another member. For groups under the democratic threshold
-- (default 10), one other member must approve. No single person
-- has unilateral removal power.

CREATE TABLE group_removal_requests (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id                UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,

    target_user_id          UUID NOT NULL REFERENCES users(id),
    requested_by_user_id    UUID NOT NULL REFERENCES users(id),

    reason                  TEXT,

    status                  removal_request_status NOT NULL DEFAULT 'PENDING',

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at              TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '7 days'),
    resolved_at             TIMESTAMPTZ,

    CONSTRAINT chk_cannot_request_self_removal
        CHECK (target_user_id != requested_by_user_id)
);
