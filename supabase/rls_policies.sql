-- ============================================================
-- GirlTea App — Row Level Security (RLS) Policies
-- ============================================================
-- These policies use auth.uid() (the Supabase-authenticated user's
-- UUID) to control access. users.id = auth.uid() links the app
-- profile to the auth identity.
--
-- Run this in the Supabase SQL Editor after creating all tables.

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
        OR EXISTS (
            SELECT 1 FROM group_memberships gm
            WHERE gm.group_id = id
              AND gm.user_id = auth.uid()
              AND gm.status = 'ACTIVE'
        )
    )
);

CREATE POLICY "Group creator can update group"
ON groups FOR UPDATE TO authenticated
USING (created_by_user_id = auth.uid())
WITH CHECK (created_by_user_id = auth.uid());

-- ============================================================
-- GROUP MEMBERSHIPS
-- ============================================================

CREATE POLICY "Members can see memberships in their groups"
ON group_memberships FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM group_memberships my_gm
        WHERE my_gm.group_id = group_memberships.group_id
          AND my_gm.user_id = auth.uid()
          AND my_gm.status = 'ACTIVE'
    )
);

-- Insert handled by approval functions (service role)

-- ============================================================
-- GROUP INVITES
-- ============================================================

CREATE POLICY "Members can create invites for their groups"
ON group_invites FOR INSERT TO authenticated
WITH CHECK (
    created_by_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = group_invites.group_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

CREATE POLICY "Members can read invites for their groups"
ON group_invites FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = group_invites.group_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

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
    OR EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = group_join_requests.group_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
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
            OR EXISTS (
                SELECT 1 FROM group_memberships gm
                WHERE gm.group_id = jr.group_id
                  AND gm.user_id = auth.uid()
                  AND gm.status = 'ACTIVE'
            )
          )
    )
);

-- ============================================================
-- GROUP JOIN VOTES
-- ============================================================
-- INSERT via fn_cast_join_vote (SECURITY DEFINER) is the intended
-- path. This policy is a safety net if direct INSERT is attempted.

CREATE POLICY "Members can cast join votes"
ON group_join_votes FOR INSERT TO authenticated
WITH CHECK (
    voter_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM group_join_requests jr
        JOIN group_memberships gm ON gm.group_id = jr.group_id
        WHERE jr.id = group_join_votes.join_request_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

CREATE POLICY "Members can see join votes in their groups"
ON group_join_votes FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM group_join_requests jr
        JOIN group_memberships gm ON gm.group_id = jr.group_id
        WHERE jr.id = group_join_votes.join_request_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

-- ============================================================
-- GROUP REMOVAL REQUESTS
-- ============================================================

CREATE POLICY "Members can create removal requests"
ON group_removal_requests FOR INSERT TO authenticated
WITH CHECK (
    requested_by_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = group_removal_requests.group_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

CREATE POLICY "Members can see removal requests in their groups"
ON group_removal_requests FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = group_removal_requests.group_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

-- ============================================================
-- GROUP REMOVAL VOTES
-- ============================================================
-- INSERT via fn_cast_removal_vote (SECURITY DEFINER) is the intended
-- path. This policy is a safety net if direct INSERT is attempted.
-- Blocks the removal target from voting on their own removal.

CREATE POLICY "Members can cast removal votes"
ON group_removal_votes FOR INSERT TO authenticated
WITH CHECK (
    voter_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM group_removal_requests rr
        JOIN group_memberships gm ON gm.group_id = rr.group_id
        WHERE rr.id = group_removal_votes.removal_request_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
          AND rr.target_user_id != auth.uid()
    )
);

CREATE POLICY "Members can see removal votes"
ON group_removal_votes FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM group_removal_requests rr
        JOIN group_memberships gm ON gm.group_id = rr.group_id
        WHERE rr.id = group_removal_votes.removal_request_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

-- ============================================================
-- POSTS
-- ============================================================

CREATE POLICY "Members can create posts in their groups"
ON posts FOR INSERT TO authenticated
WITH CHECK (
    author_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = posts.group_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

CREATE POLICY "Members can read posts in their groups"
ON posts FOR SELECT TO authenticated
USING (
    is_deleted = FALSE
    AND EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = posts.group_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

CREATE POLICY "Authors can update their own posts"
ON posts FOR UPDATE TO authenticated
USING (author_user_id = auth.uid())
WITH CHECK (author_user_id = auth.uid());

-- ============================================================
-- COMMENTS
-- ============================================================

CREATE POLICY "Members can create comments on posts in their groups"
ON comments FOR INSERT TO authenticated
WITH CHECK (
    author_user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM posts p
        JOIN group_memberships gm ON gm.group_id = p.group_id
        WHERE p.id = comments.post_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

CREATE POLICY "Members can read comments on posts in their groups"
ON comments FOR SELECT TO authenticated
USING (
    is_deleted = FALSE
    AND EXISTS (
        SELECT 1 FROM posts p
        JOIN group_memberships gm ON gm.group_id = p.group_id
        WHERE p.id = comments.post_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

CREATE POLICY "Authors can update their own comments"
ON comments FOR UPDATE TO authenticated
USING (author_user_id = auth.uid())
WITH CHECK (author_user_id = auth.uid());

-- ============================================================
-- POST UPVOTES
-- ============================================================

CREATE POLICY "Members can upvote posts in their groups"
ON post_upvotes FOR INSERT TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
        SELECT 1 FROM posts p
        JOIN group_memberships gm ON gm.group_id = p.group_id
        WHERE p.id = post_upvotes.post_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
    )
);

CREATE POLICY "Members can see upvotes on posts in their groups"
ON post_upvotes FOR SELECT TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM posts p
        JOIN group_memberships gm ON gm.group_id = p.group_id
        WHERE p.id = post_upvotes.post_id
          AND gm.user_id = auth.uid()
          AND gm.status = 'ACTIVE'
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
