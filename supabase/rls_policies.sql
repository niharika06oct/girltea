-- ============================================================
-- GirlTea App — Row Level Security (RLS) Policies
-- ============================================================
-- All membership checks use fn_is_group_member() (SECURITY DEFINER).
-- Post-related checks use fn_post_group() (SECURITY DEFINER) since
-- SELECT on posts is revoked from authenticated.
--
-- Posts/comments: read through views, write to base tables.
-- Memberships: read through view, write via DEFINER functions.
--
-- Run auth_helpers.sql BEFORE this file.
-- Requires: pgcrypto extension.

-- ============================================================
-- Enable RLS on all tables
-- ============================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_entry_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_join_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_join_request_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_join_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_removal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_removal_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_upvotes ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_actions ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- USERS
-- ============================================================

CREATE POLICY "Users can create their own profile"
ON users FOR INSERT TO authenticated
WITH CHECK (id = auth.uid());

CREATE POLICY "Users can read their own profile"
ON users FOR SELECT TO authenticated
USING (id = auth.uid());

CREATE POLICY "Users can update their own profile"
ON users FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- ============================================================
-- GROUPS
-- ============================================================

CREATE POLICY "Authenticated users can create groups"
ON groups FOR INSERT TO authenticated
WITH CHECK (created_by_user_id = auth.uid());

CREATE POLICY "Members can read their groups"
ON groups FOR SELECT TO authenticated
USING (
    is_deleted = FALSE
    AND (
        visibility = 'DISCOVERABLE'
        OR fn_is_group_member(id)
    )
);

-- FIX #4: Use OWNER role, not created_by_user_id. Ownership is
-- transferable; the creator field is immutable history, not authority.
CREATE POLICY "Owners can update group settings"
ON groups FOR UPDATE TO authenticated
USING (fn_is_group_owner(id))
WITH CHECK (fn_is_group_owner(id));

-- ============================================================
-- GROUP MEMBERSHIPS
-- ============================================================
-- FIX #2: SELECT revoked from authenticated. Clients read through
-- group_members_view which hides user_id (prevents alias→UUID
-- mapping that defeats per-group anonymity).

-- No SELECT policy needed — view handles reads via DEFINER.

-- Direct INSERT only for creator adding themselves.
-- All other memberships created by fn_cast_join_vote (DEFINER).
CREATE POLICY "Creator can add themselves on group creation"
ON group_memberships FOR INSERT TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM groups g
        WHERE g.id = group_memberships.group_id
          AND g.created_by_user_id = auth.uid()
    )
);

-- ============================================================
-- GROUP INVITES
-- ============================================================

CREATE POLICY "Members can create invites for their groups"
ON group_invites FOR INSERT TO authenticated
WITH CHECK (
    created_by_user_id = auth.uid()
    AND fn_is_group_member(group_id)
);

CREATE POLICY "Members can read invites for their groups"
ON group_invites FOR SELECT TO authenticated
USING (fn_is_group_member(group_id));

-- FIX gap: allow revoking invites
CREATE POLICY "Members can revoke invites in their groups"
ON group_invites FOR UPDATE TO authenticated
USING (fn_is_group_member(group_id));

-- ============================================================
-- GROUP ENTRY QUESTIONS
-- ============================================================
-- FIX #5: USING(TRUE) leaked every private room's questions and
-- group_id. Non-members see questions ONLY via fn_resolve_invite.

CREATE POLICY "Members can read entry questions for their groups"
ON group_entry_questions FOR SELECT TO authenticated
USING (fn_is_group_member(group_id));

-- FIX #4: Use OWNER role for question management
CREATE POLICY "Owners can manage entry questions"
ON group_entry_questions FOR INSERT TO authenticated
WITH CHECK (fn_is_group_owner(group_id));

CREATE POLICY "Owners can update entry questions"
ON group_entry_questions FOR UPDATE TO authenticated
USING (fn_is_group_owner(group_id));

-- ============================================================
-- GROUP JOIN REQUESTS
-- ============================================================

CREATE POLICY "Users can create join requests"
ON group_join_requests FOR INSERT TO authenticated
WITH CHECK (requester_user_id = auth.uid());

CREATE POLICY "Requester and group members can see join requests"
ON group_join_requests FOR SELECT TO authenticated
USING (
    requester_user_id = auth.uid()
    OR fn_is_group_member(group_id)
);

-- FIX gap: requester can cancel their own pending request
CREATE POLICY "Requester can cancel their own request"
ON group_join_requests FOR UPDATE TO authenticated
USING (requester_user_id = auth.uid())
WITH CHECK (requester_user_id = auth.uid());

-- ============================================================
-- GROUP JOIN REQUEST ANSWERS
-- ============================================================

CREATE POLICY "Requester can create answers"
ON group_join_request_answers FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM group_join_requests jr
        WHERE jr.id = group_join_request_answers.join_request_id
          AND jr.requester_user_id = auth.uid()
    )
);

CREATE POLICY "Requester and group members can read answers"
ON group_join_request_answers FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM group_join_requests jr
        WHERE jr.id = group_join_request_answers.join_request_id
          AND (
            jr.requester_user_id = auth.uid()
            OR fn_is_group_member(jr.group_id)
          )
    )
);

-- ============================================================
-- GROUP JOIN VOTES
-- ============================================================
-- Intended path: fn_cast_join_vote (SECURITY DEFINER).
-- RLS is the safety net for direct INSERT attempts.

CREATE POLICY "Members can cast join votes"
ON group_join_votes FOR INSERT TO authenticated
WITH CHECK (
    voter_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM group_join_requests jr
        WHERE jr.id = group_join_votes.join_request_id
          AND jr.requester_user_id != auth.uid()
          AND fn_is_group_member(jr.group_id)
    )
);

CREATE POLICY "Members can see join votes in their groups"
ON group_join_votes FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM group_join_requests jr
        WHERE jr.id = group_join_votes.join_request_id
          AND fn_is_group_member(jr.group_id)
    )
);

-- ============================================================
-- GROUP REMOVAL REQUESTS
-- ============================================================

CREATE POLICY "Members can create removal requests"
ON group_removal_requests FOR INSERT TO authenticated
WITH CHECK (
    requested_by_user_id = auth.uid()
    AND fn_is_group_member(group_id)
);

CREATE POLICY "Members can see removal requests in their groups"
ON group_removal_requests FOR SELECT TO authenticated
USING (fn_is_group_member(group_id));

-- ============================================================
-- GROUP REMOVAL VOTES
-- ============================================================
-- Intended path: fn_cast_removal_vote (SECURITY DEFINER).

CREATE POLICY "Members can cast removal votes"
ON group_removal_votes FOR INSERT TO authenticated
WITH CHECK (
    voter_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM group_removal_requests rr
        WHERE rr.id = group_removal_votes.removal_request_id
          AND rr.target_user_id != auth.uid()
          AND fn_is_group_member(rr.group_id)
    )
);

CREATE POLICY "Members can see removal votes"
ON group_removal_votes FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM group_removal_requests rr
        WHERE rr.id = group_removal_votes.removal_request_id
          AND fn_is_group_member(rr.group_id)
    )
);

-- ============================================================
-- POSTS (base table)
-- ============================================================
-- SELECT revoked (see bottom). Clients read through posts_feed.
-- FIX #1: INSERT uses fn_is_group_member(group_id) — no subquery
-- on posts needed since the group_id comes from the INSERT values.
-- FIX #6: No DELETE policy. Soft-delete via UPDATE only.

CREATE POLICY "Members can create posts in their groups"
ON posts FOR INSERT TO authenticated
WITH CHECK (
    author_user_id = auth.uid()
    AND fn_is_group_member(group_id)
);

-- FIX #3: Only body/media/thumbnail are updatable. Immutable columns
-- (author_alias, author_user_id, group_id, type) are locked by trigger.
CREATE POLICY "Authors can update their own posts"
ON posts FOR UPDATE TO authenticated
USING (fn_is_post_author(id))
WITH CHECK (fn_is_post_author(id));

-- ============================================================
-- COMMENTS (base table)
-- ============================================================
-- FIX #1: Uses fn_post_group() instead of subquery on posts.
-- FIX #6: No DELETE policy. Soft-delete via UPDATE only.

CREATE POLICY "Members can create comments on posts in their groups"
ON comments FOR INSERT TO authenticated
WITH CHECK (
    author_user_id = auth.uid()
    AND fn_is_group_member(fn_post_group(post_id))
);

-- FIX #3: Same column-lock trigger as posts.
CREATE POLICY "Authors can update their own comments"
ON comments FOR UPDATE TO authenticated
USING (fn_is_comment_author(id))
WITH CHECK (fn_is_comment_author(id));

-- ============================================================
-- POST UPVOTES
-- ============================================================
-- FIX #1: Uses fn_post_group() instead of subquery on posts.

CREATE POLICY "Members can upvote posts in their groups"
ON post_upvotes FOR INSERT TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND fn_is_group_member(fn_post_group(post_id))
);

CREATE POLICY "Members can see upvotes on posts in their groups"
ON post_upvotes FOR SELECT TO authenticated
USING (fn_is_group_member(fn_post_group(post_id)));

CREATE POLICY "Users can remove their own upvotes"
ON post_upvotes FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- REPORTS
-- ============================================================

-- Reporters file through fn_submit_report (DEFINER), which snapshots
-- evidence. This RLS is the safety net for direct INSERT attempts:
-- a client may only file as itself, and only PENDING (can't backdate
-- a status or self-assign).
CREATE POLICY "Authenticated users can create reports"
ON reports FOR INSERT TO authenticated
WITH CHECK (
    reporter_user_id = auth.uid()
    AND status = 'PENDING'
    AND assigned_to_user_id IS NULL
    AND resolved_at IS NULL
);

CREATE POLICY "Users can see their own reports"
ON reports FOR SELECT TO authenticated
USING (reporter_user_id = auth.uid());

-- Moderation (triage, assign, action, dismiss) runs through
-- SECURITY DEFINER RPCs in 022_moderation.sql, which enforce the
-- moderator role. No direct UPDATE policy — reporters cannot mutate
-- their report's status, and non-moderators cannot touch others'.
-- service_role retains full access for dashboard/Edge Function use.

-- ---- Report actions (audit log) ----
-- Append-only, written only by DEFINER moderation RPCs. Reporters may
-- read the action trail on their own reports for transparency.
CREATE POLICY "Reporters can read actions on their own reports"
ON report_actions FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM reports r
        WHERE r.id = report_actions.report_id
          AND r.reporter_user_id = auth.uid()
    )
);

-- ============================================================
-- ANONYMITY: Views + privilege revocation
-- ============================================================

-- ---- Posts feed ----
CREATE OR REPLACE VIEW posts_feed WITH (security_barrier = true) AS
SELECT
    p.id,
    p.group_id,
    p.author_alias,
    p.type,
    p.body,
    p.media_url,
    p.duration_seconds,
    p.thumbnail_url,
    p.upvote_count,
    p.created_at,
    p.updated_at,
    (p.author_user_id = auth.uid()) AS is_mine
FROM posts p
WHERE p.is_deleted = FALSE
  AND fn_is_group_member(p.group_id);

-- ---- Comments feed ----
CREATE OR REPLACE VIEW comments_feed WITH (security_barrier = true) AS
SELECT
    c.id,
    c.post_id,
    c.parent_comment_id,
    c.author_alias,
    c.type,
    c.body,
    c.media_url,
    c.duration_seconds,
    c.created_at,
    c.updated_at,
    (c.author_user_id = auth.uid()) AS is_mine
FROM comments c
JOIN posts p ON p.id = c.post_id
WHERE c.is_deleted = FALSE
  AND fn_is_group_member(p.group_id);

-- ---- Group members feed ----
-- FIX #2: Hides user_id. Prevents alias→UUID deanonymization
-- and cross-group identity correlation.
CREATE OR REPLACE VIEW group_members_view WITH (security_barrier = true) AS
SELECT
    gm.group_id,
    gm.alias,
    gm.role,
    gm.joined_at,
    (gm.user_id = auth.uid()) AS is_me
FROM group_memberships gm
WHERE gm.status = 'ACTIVE'
  AND fn_is_group_member(gm.group_id);

-- ---- Revoke direct SELECT ----
REVOKE SELECT ON posts FROM authenticated;
REVOKE SELECT ON posts FROM anon;
REVOKE SELECT ON comments FROM authenticated;
REVOKE SELECT ON comments FROM anon;
REVOKE SELECT ON group_memberships FROM authenticated;
REVOKE SELECT ON group_memberships FROM anon;

GRANT SELECT ON posts_feed TO authenticated;
GRANT SELECT ON comments_feed TO authenticated;
GRANT SELECT ON group_members_view TO authenticated;
