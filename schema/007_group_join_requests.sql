-- ============================================================
-- GirlTea App — Group Join Requests
-- ============================================================
-- Suggestion incorporated: source enum (INVITE_LINK, SUGGESTION,
-- MANUAL_SEARCH) for funnel analytics.

CREATE TABLE group_join_requests (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id            UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    requester_user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    status              join_request_status NOT NULL DEFAULT 'PENDING',
    source              join_request_source,

    invite_id           UUID REFERENCES group_invites(id),

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at          TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '14 days'),
    resolved_at         TIMESTAMPTZ
);
