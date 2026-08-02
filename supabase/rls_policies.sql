-- ============================================================
-- GirlTea App — Row Level Security (RLS) Policies
-- ============================================================
-- All membership checks use fn_is_group_member() (SECURITY DEFINER)
-- to avoid infinite recursion on group_memberships.
--
-- Posts and comments are accessed ONLY through views (posts_feed,
-- comments_feed) that omit author_user_id. Direct SELECT on base
-- tables is revoked from authenticated.
--
-- Run auth_helpers.sql BEFORE this file.

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

CREATE POLICY "Group creator can update group"
ON groups FOR UPDATE TO authenticated
USING (created_by_user_id = auth.uid())
WITH CHECK (created_by_user_id = auth.uid());

-- ============================================================
-- GROUP MEMBERSHIPS
-- ============================================================
-- Uses fn_is_group_member() to avoid infinite recursion.

CREATE POLICY "Members can see memberships in their groups"
ON group_memberships FOR SELECT TO authenticated
USING (fn_is_group_member(group_id));

-- Direct INSERT is NOT allowed. Memberships are created only by
-- fn_cast_join_vote (SECURITY DEFINER) when quorum is reached,
-- or by the group creator adding themselves.

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

-- ============================================================
-- GROUP ENTRY QUESTIONS
-- ============================================================

CREATE POLICY "Anyone authenticated can read entry questions"
ON group_entry_questions FOR SELECT TO authenticated
USING (TRUE);

CREATE POLICY "Group creator can manage entry questions"
ON group_entry_questions FOR INSERT TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM groups g
        WHERE g.id = group_entry_questions.group_id
          AND g.created_by_user_id = auth.uid()
    )
);

CREATE POLICY "Group creator can update entry questions"
ON group_entry_questions FOR UPDATE TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM groups g
        WHERE g.id = group_entry_questions.group_id
          AND g.created_by_user_id = auth.uid()
    )
);

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
-- Blocks: non-members, voter_id forgery, requester self-voting.

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
-- RLS blocks: non-members, voter_id forgery, target self-voting.

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
-- SELECT on posts is revoked from authenticated (see below).
-- Clients read through posts_feed view which omits author_user_id.
-- INSERT/UPDATE/DELETE policies remain on the base table.

CREATE POLICY "Members can create posts in their groups"
ON posts FOR INSERT TO authenticated
WITH CHECK (
    author_user_id = auth.uid()
    AND fn_is_group_member(group_id)
);

CREATE POLICY "Authors can update their own posts"
ON posts FOR UPDATE TO authenticated
USING (author_user_id = auth.uid())
WITH CHECK (author_user_id = auth.uid());

CREATE POLICY "Authors can soft-delete their own posts"
ON posts FOR DELETE TO authenticated
USING (author_user_id = auth.uid());

-- ============================================================
-- COMMENTS (base table)
-- ============================================================
-- Same pattern: SELECT revoked, clients use comments_feed view.

CREATE POLICY "Members can create comments on posts in their groups"
ON comments FOR INSERT TO authenticated
WITH CHECK (
    author_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM posts p
        WHERE p.id = comments.post_id
          AND fn_is_group_member(p.group_id)
    )
);

CREATE POLICY "Authors can update their own comments"
ON comments FOR UPDATE TO authenticated
USING (author_user_id = auth.uid())
WITH CHECK (author_user_id = auth.uid());

CREATE POLICY "Authors can soft-delete their own comments"
ON comments FOR DELETE TO authenticated
USING (author_user_id = auth.uid());

-- ============================================================
-- POST UPVOTES
-- ============================================================

CREATE POLICY "Members can upvote posts in their groups"
ON post_upvotes FOR INSERT TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM posts p
        WHERE p.id = post_upvotes.post_id
          AND fn_is_group_member(p.group_id)
    )
);

CREATE POLICY "Members can see upvotes on posts in their groups"
ON post_upvotes FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM posts p
        WHERE p.id = post_upvotes.post_id
          AND fn_is_group_member(p.group_id)
    )
);

CREATE POLICY "Users can remove their own upvotes"
ON post_upvotes FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- REPORTS
-- ============================================================

CREATE POLICY "Authenticated users can create reports"
ON reports FOR INSERT TO authenticated
WITH CHECK (reporter_user_id = auth.uid());

CREATE POLICY "Users can see their own reports"
ON reports FOR SELECT TO authenticated
USING (reporter_user_id = auth.uid());

-- ============================================================
-- ANONYMITY: Views + privilege revocation
-- ============================================================
-- Posts and comments are exposed ONLY through views that omit
-- author_user_id. The views provide an is_mine boolean so the
-- client knows which posts/comments belong to the current user
-- (for edit/delete UI) without revealing the identity.
--
-- security_barrier prevents the optimizer from leaking data
-- through predicate pushdown.

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

CREATE OR REPLACE VIEW comments_feed WITH (security_barrier = true) AS
SELECT
    c.id,
    c.post_id,
    c.author_alias,
    c.type,
    c.body,
    c.media_url,
    c.duration_seconds,
    c.created_at,
    c.updated_at,
    (c.author_user_id = auth.uid()) AS is_mine
FROM comments c
WHERE c.is_deleted = FALSE
  AND EXISTS (
      SELECT 1 FROM posts p
      WHERE p.id = c.post_id
        AND fn_is_group_member(p.group_id)
  );

-- Revoke direct SELECT on base tables from client-facing roles.
-- INSERT/UPDATE/DELETE still work through RLS policies above.
-- SECURITY DEFINER functions (moderation, approval) can still read.

REVOKE SELECT ON posts FROM authenticated;
REVOKE SELECT ON posts FROM anon;
REVOKE SELECT ON comments FROM authenticated;
REVOKE SELECT ON comments FROM anon;

GRANT SELECT ON posts_feed TO authenticated;
GRANT SELECT ON comments_feed TO authenticated;
