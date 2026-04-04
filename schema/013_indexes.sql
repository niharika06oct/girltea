-- ============================================================
-- GirlTea App — Indexes
-- ============================================================
-- Suggestion incorporated: partial indexes for common query
-- patterns and day-1 performance.

-- ---- Users ----
CREATE INDEX idx_users_auth_subject ON users (auth_subject);
CREATE INDEX idx_users_country_code ON users (country_code);
CREATE INDEX idx_users_not_deleted ON users (id) WHERE is_deleted = FALSE;

-- ---- Groups ----
-- Suggest groups to a user (discoverable only)
CREATE INDEX idx_groups_discoverable ON groups (visibility, policy)
    WHERE visibility = 'DISCOVERABLE' AND is_deleted = FALSE;

CREATE INDEX idx_groups_category_tags ON groups USING GIN (category_tags);

-- Partial index on approval quorum setting for discoverable groups
CREATE INDEX idx_groups_approval_quorum ON groups ((settings->>'memberApproverQuorum'))
    WHERE visibility = 'DISCOVERABLE';

CREATE INDEX idx_groups_created_by ON groups (created_by_user_id);

-- ---- Group Memberships ----
CREATE INDEX idx_memberships_user ON group_memberships (user_id, status);
CREATE INDEX idx_memberships_group_active ON group_memberships (group_id)
    WHERE status = 'ACTIVE';

-- ---- Group Invites ----
CREATE INDEX idx_invites_group ON group_invites (group_id);
CREATE INDEX idx_invites_token ON group_invites (token_hash);

-- ---- Group Entry Questions ----
CREATE INDEX idx_entry_questions_group ON group_entry_questions (group_id, sort_order);

-- ---- Join Requests ----
-- Which requests a member can vote on
CREATE INDEX idx_join_requests_group_pending ON group_join_requests (group_id, status)
    WHERE status = 'PENDING';

-- One pending request per user per group
CREATE UNIQUE INDEX uq_one_pending_request_per_user_group
    ON group_join_requests (group_id, requester_user_id)
    WHERE status = 'PENDING';

CREATE INDEX idx_join_requests_requester ON group_join_requests (requester_user_id, status);
CREATE INDEX idx_join_requests_expires ON group_join_requests (expires_at)
    WHERE status = 'PENDING';

-- ---- Join Request Answers ----
CREATE INDEX idx_join_answers_request ON group_join_request_answers (join_request_id);

-- ---- Join Votes ----
CREATE INDEX idx_join_votes_request ON group_join_votes (join_request_id, vote);

-- ---- Posts ----
-- Feed query: posts in a group, newest first
CREATE INDEX idx_posts_group_feed ON posts (group_id, created_at DESC)
    WHERE is_deleted = FALSE;

CREATE INDEX idx_posts_author ON posts (author_user_id);

-- ---- Comments ----
CREATE INDEX idx_comments_post ON comments (post_id, created_at)
    WHERE is_deleted = FALSE;

-- ---- Removal Requests ----
CREATE INDEX idx_removal_requests_group_pending ON group_removal_requests (group_id, status)
    WHERE status = 'PENDING';

CREATE UNIQUE INDEX uq_one_pending_removal_per_target
    ON group_removal_requests (group_id, target_user_id)
    WHERE status = 'PENDING';

CREATE INDEX idx_removal_requests_target ON group_removal_requests (target_user_id, status);
CREATE INDEX idx_removal_requests_expires ON group_removal_requests (expires_at)
    WHERE status = 'PENDING';

-- ---- Removal Votes ----
CREATE INDEX idx_removal_votes_request ON group_removal_votes (removal_request_id, vote);

-- ---- Reports ----
CREATE INDEX idx_reports_target ON reports (target_type, target_id);
CREATE INDEX idx_reports_unresolved ON reports (created_at)
    WHERE resolved = FALSE;
