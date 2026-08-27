-- ============================================================
-- GirlTea App — Migration 026: Saved Posts (Memories)
-- ============================================================
-- Additive. A private, owner-only keepsake archive: a member can save any
-- post from a circle they belong to. Powers the "Memories" scrapbook.
-- No auto-expiry, no deletion of source posts — this is a bookmark, not a
-- countdown. Saves cascade away if the user or the post is deleted.
--
-- Follows the app's read/write split: writes to the base table (RLS-gated),
-- reads through a security_barrier view that reuses the posts_feed shape and
-- never exposes author_user_id.
--
-- Apply order: after posts (010), auth_helpers, rls_policies. Idempotent.

-- ---- Table ----
CREATE TABLE IF NOT EXISTS saved_posts (
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, post_id)
);

-- Fast "my memories, newest first".
CREATE INDEX IF NOT EXISTS idx_saved_posts_user_created
    ON saved_posts (user_id, created_at DESC);

-- ---- Table privileges (RLS narrows these) ----
GRANT SELECT, INSERT, DELETE ON saved_posts TO authenticated;

-- ---- RLS: owner-only ----
ALTER TABLE saved_posts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can save posts in their groups" ON saved_posts;
CREATE POLICY "Users can save posts in their groups"
ON saved_posts FOR INSERT TO authenticated
WITH CHECK (
    user_id = auth.uid()
    AND fn_is_group_member(fn_post_group(post_id))
);

DROP POLICY IF EXISTS "Users can read their own saved posts" ON saved_posts;
CREATE POLICY "Users can read their own saved posts"
ON saved_posts FOR SELECT TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can unsave their own saved posts" ON saved_posts;
CREATE POLICY "Users can unsave their own saved posts"
ON saved_posts FOR DELETE TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- saved_posts_feed — the Memories read model
-- ============================================================
-- Same safe post columns as posts_feed (never author_user_id), plus the
-- moment it was saved. A view runs with its owner's privileges, so it may
-- read the posts base table even though SELECT on posts is revoked from
-- authenticated — exactly as posts_feed does. Membership is re-checked so a
-- save can't outlive losing access to the circle, and only the caller's own
-- saves are returned.
CREATE OR REPLACE VIEW saved_posts_feed WITH (security_barrier = true) AS
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
    (p.author_user_id = auth.uid()) AS is_mine,
    sp.created_at AS saved_at
FROM saved_posts sp
JOIN posts p ON p.id = sp.post_id
WHERE sp.user_id = auth.uid()
  AND p.is_deleted = FALSE
  AND fn_is_group_member(p.group_id);

GRANT SELECT ON saved_posts_feed TO authenticated;
