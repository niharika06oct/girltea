-- ============================================================
-- GirlTea App — Post Upvotes (tea drops)
-- ============================================================
-- Tracks who upvoted which post. Prevents double-tapping via
-- unique constraint. Trigger maintains posts.upvote_count.

CREATE TABLE post_upvotes (
    post_id     UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (post_id, user_id)
);
