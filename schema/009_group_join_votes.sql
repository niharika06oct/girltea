-- ============================================================
-- GirlTea App — Group Join Votes (approvals / rejections)
-- ============================================================
-- Suggestion incorporated: voter_role tracks the role at vote time
-- so quorum logic changes don't require re-computation.

CREATE TABLE group_join_votes (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    join_request_id     UUID NOT NULL REFERENCES group_join_requests(id) ON DELETE CASCADE,
    voter_user_id       UUID NOT NULL REFERENCES users(id),

    vote                vote_decision NOT NULL,
    voter_role          membership_role NOT NULL,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_one_vote_per_voter_per_request
        UNIQUE (join_request_id, voter_user_id)
);
