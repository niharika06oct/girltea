-- ============================================================
-- GirlTea App — Migration 029: Mint invite links (any member)
-- ============================================================
-- Additive. Lets ANY active member of a circle mint a shareable invite
-- link. The token is generated server-side (SECURITY DEFINER) so the client
-- never needs a crypto dependency, and the raw token is returned exactly
-- once — only its sha256 hash is stored, matching what fn_resolve_invite /
-- fn_submit_join_request already expect (encode(digest(token,'sha256'),'hex')).
--
-- This mints a LINK only. It grants no membership: whoever opens the link
-- still goes through the existing democratic join flow (fn_submit_join_request
-- -> fn_cast_join_vote), which admits them only after 2 members approve.
--
-- Apply order: after 005_group_invites, 021_hub_rpcs. Idempotent.

CREATE OR REPLACE FUNCTION fn_create_invite(
    p_group_id   UUID,
    p_max_uses   INT DEFAULT NULL,
    p_expires_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS TEXT AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_token  TEXT;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Any ACTIVE member of the circle may invite.
    IF NOT EXISTS (
        SELECT 1 FROM group_memberships gm
        WHERE gm.group_id = p_group_id
          AND gm.user_id = v_caller
          AND gm.status = 'ACTIVE'
    ) THEN
        RAISE EXCEPTION 'Only members of this circle can create invites';
    END IF;

    IF p_max_uses IS NOT NULL AND p_max_uses <= 0 THEN
        RAISE EXCEPTION 'max_uses must be positive';
    END IF;

    -- URL-safe, unguessable token; only its hash is persisted.
    v_token := encode(gen_random_bytes(24), 'hex');

    INSERT INTO group_invites (group_id, token_hash, created_by_user_id, max_uses, expires_at)
    VALUES (
        p_group_id,
        encode(digest(v_token, 'sha256'), 'hex'),
        v_caller,
        p_max_uses,
        p_expires_at
    );

    RETURN v_token;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;

REVOKE ALL ON FUNCTION fn_create_invite(UUID, INT, TIMESTAMPTZ) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION fn_create_invite(UUID, INT, TIMESTAMPTZ) TO authenticated;
