-- ============================================================
-- GirlTea App — Migration 027: Post Reactions
-- ============================================================
-- Additive and layered ON TOP of the existing binary post_upvotes /
-- upvote_count — those are untouched, so nothing that reads upvotes breaks.
-- Reactions are the expressive set from the mockup: ❤️ 🫂 😭 😂 ☕ ✨.
-- A member may add several distinct reactions to a post, but each (post,
-- user, type) only once.
--
-- Anonymity preserved: the read model exposes the reactor's per-group ALIAS
-- (never user_id / real name), so the UI can say "VelvetPhoenix04 sent love"
-- without leaking identity — same guarantee as posts_feed.
--
-- Apply order: after posts (010), auth_helpers, rls_policies. Idempotent.

-- ---- Table ----
CREATE TABLE IF NOT EXISTS post_reactions (
    post_id        UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reaction_type  TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (post_id, user_id, reaction_type),

    CONSTRAINT chk_reaction_type
        CHECK (reaction_type IN ('LOVE','HUG','CRY','LAUGH','TEA','SPARK'))
);

CREATE INDEX IF NOT EXISTS idx_post_reactions_post
    ON post_reactions (post_id);

-- ---- Table privileges (RLS narrows these) ----
GRANT SELECT, INSERT, DELETE ON post_reactions TO authenticated;

-- ---- RLS: group members react; users manage only their own ----
ALTER TABLE post_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Members can react to posts in their groups" ON post_reactions;
CREATE POLICY "Members can react to posts in their groups"
ON post_reactions FOR INSERT TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND fn_is_group_member(fn_post_group(post_id))
);

DROP POLICY IF EXISTS "Members can see reactions in their groups" ON post_reactions;
CREATE POLICY "Members can see reactions in their groups"
ON post_reactions FOR SELECT TO authenticated
USING (fn_is_group_member(fn_post_group(post_id)));

DROP POLICY IF EXISTS "Users can remove their own reactions" ON post_reactions;
CREATE POLICY "Users can remove their own reactions"
ON post_reactions FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- post_reactions_feed — reactions read model (alias, not identity)
-- ============================================================
-- Joins each reaction to the reactor's ACTIVE alias in the post's group.
-- Never exposes user_id. is_mine lets the client highlight the caller's own
-- reactions and toggle them. Membership is re-checked via the join to the
-- post's group so non-members see nothing.
CREATE OR REPLACE VIEW post_reactions_feed WITH (security_barrier = true) AS
SELECT
    pr.post_id,
    p.group_id,
    pr.reaction_type,
    gm.alias AS author_alias,
    pr.created_at,
    (pr.user_id = auth.uid()) AS is_mine
FROM post_reactions pr
JOIN posts p ON p.id = pr.post_id
JOIN group_memberships gm
    ON gm.group_id = p.group_id
   AND gm.user_id = pr.user_id
WHERE p.is_deleted = FALSE
  AND fn_is_group_member(p.group_id);

GRANT SELECT ON post_reactions_feed TO authenticated;
