-- ============================================================
-- GirlTea App — Group Removal Votes
-- ============================================================
-- Tracks approval/rejection of removal requests. The requester's
-- intent counts as the first vote; one more member must approve
-- for the removal to go through (for groups under democratic
-- threshold). Larger groups use the configured removalQuorum.

CREATE TABLE group_removal_votes (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    removal_request_id      UUID NOT NULL REFERENCES group_removal_requests(id) ON DELETE CASCADE,
    voter_user_id           UUID NOT NULL REFERENCES users(id),

    vote                    vote_decision NOT NULL,
    voter_role              membership_role NOT NULL,

    created_at              TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_one_removal_vote_per_voter
        UNIQUE (removal_request_id, voter_user_id)
);
