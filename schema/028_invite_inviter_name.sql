-- ============================================================
-- GirlTea App — Migration 028: Inviter name on invite resolve
-- ============================================================
-- Additive. Extends fn_resolve_invite to also return the inviter's
-- display_name, so the invite landing can say "Niharika saved you a seat ☕".
-- No new columns; reads the existing group_invites.created_by_user_id and
-- joins users. Still returns ONLY safe metadata — never the member list or
-- posts. Changing a function's RETURNS TABLE shape requires DROP + CREATE.
--
-- Apply order: after 021_hub_rpcs. Idempotent.

DROP FUNCTION IF EXISTS fn_resolve_invite(TEXT);

CREATE OR REPLACE FUNCTION fn_resolve_invite(p_token TEXT)
RETURNS TABLE (
    group_id UUID,
    name TEXT,
    description TEXT,
    policy group_policy,
    member_count INT,
    questions JSONB,
    already_member BOOLEAN,
    has_pending_request BOOLEAN,
    inviter_name TEXT
) AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_token_hash TEXT;
    v_invite_id UUID;
    v_group_id UUID;
    v_inviter_user UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_token_hash := encode(digest(p_token, 'sha256'), 'hex');

    SELECT gi.id, gi.group_id, gi.created_by_user_id
    INTO v_invite_id, v_group_id, v_inviter_user
    FROM group_invites gi
    WHERE gi.token_hash = v_token_hash
      AND gi.revoked_at IS NULL
      AND (gi.expires_at IS NULL OR gi.expires_at > now())
      AND (gi.max_uses IS NULL OR gi.use_count < gi.max_uses);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite link is invalid, expired, or revoked';
    END IF;

    RETURN QUERY
    SELECT
        g.id,
        g.name,
        g.description,
        g.policy,
        g.member_count,
        COALESCE(
            (SELECT jsonb_agg(jsonb_build_object(
                'id', eq.id,
                'sort_order', eq.sort_order,
                'prompt', eq.prompt,
                'question_type', eq.question_type,
                'options', eq.options,
                'is_required', eq.is_required,
                'version', eq.version
            ) ORDER BY eq.sort_order)
            FROM group_entry_questions eq
            WHERE eq.group_id = g.id),
            '[]'::JSONB
        ),
        EXISTS (
            SELECT 1 FROM group_memberships gm
            WHERE gm.group_id = g.id
              AND gm.user_id = v_caller
              AND gm.status = 'ACTIVE'
        ),
        EXISTS (
            SELECT 1 FROM group_join_requests jr
            WHERE jr.group_id = g.id
              AND jr.requester_user_id = v_caller
              AND jr.status = 'PENDING'
        ),
        (SELECT u.display_name
         FROM users u
         WHERE u.id = v_inviter_user
           AND u.is_deleted = FALSE)
    FROM groups g
    WHERE g.id = v_group_id
      AND g.is_deleted = FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;
