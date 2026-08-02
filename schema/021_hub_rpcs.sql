-- ============================================================
-- GirlTea App — Hub RPCs
-- ============================================================
-- Four functions the hub screen depends on. All SECURITY DEFINER
-- with locked search_path. All derive caller from auth.uid().

-- ============================================================
-- fn_create_group_with_owner
-- ============================================================
-- Atomically: create group + insert owner membership with alias.
-- Returns the new group's UUID.

CREATE OR REPLACE FUNCTION fn_create_group_with_owner(
    p_name TEXT,
    p_description TEXT DEFAULT NULL,
    p_policy group_policy DEFAULT 'GENDER_NEUTRAL',
    p_visibility group_visibility DEFAULT 'LINK_ONLY',
    p_category_tags TEXT[] DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_group_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    PERFORM 1 FROM users
    WHERE id = v_caller AND is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found — complete onboarding first';
    END IF;

    INSERT INTO groups (name, description, policy, visibility, category_tags, created_by_user_id)
    VALUES (p_name, p_description, p_policy, p_visibility, p_category_tags, v_caller)
    RETURNING id INTO v_group_id;

    INSERT INTO group_memberships (group_id, user_id, role, status, alias)
    VALUES (v_group_id, v_caller, 'OWNER', 'ACTIVE', fn_generate_alias());

    RETURN v_group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_resolve_invite
-- ============================================================
-- Accepts a raw token (NOT a hash). Hashes it internally and
-- looks up the invite. Returns only safe metadata: group name,
-- description, policy, member count, entry questions. Never
-- the member list, never posts.
--
-- Also tells the caller whether they're already a member or
-- have a pending request (so the UI can skip the join form).
--
-- Rate-limit note: Supabase Edge Function or API gateway should
-- throttle calls to this by auth.uid() (e.g. 10/min) to prevent
-- brute-forcing tokens into a group-name oracle.

CREATE OR REPLACE FUNCTION fn_resolve_invite(p_token TEXT)
RETURNS TABLE (
    group_id UUID,
    name TEXT,
    description TEXT,
    policy group_policy,
    member_count INT,
    questions JSONB,
    already_member BOOLEAN,
    has_pending_request BOOLEAN
) AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_token_hash TEXT;
    v_invite_id UUID;
    v_group_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_token_hash := encode(digest(p_token, 'sha256'), 'hex');

    SELECT gi.id, gi.group_id
    INTO v_invite_id, v_group_id
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
        )
    FROM groups g
    WHERE g.id = v_group_id
      AND g.is_deleted = FALSE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;


-- ============================================================
-- fn_submit_join_request
-- ============================================================
-- Atomically creates a join request AND its answer rows.
-- Without this, a member could see a request with no answers
-- (blank form to vote on).
--
-- p_answers: JSONB array of { question_id, question_version, answer_text }

CREATE OR REPLACE FUNCTION fn_submit_join_request(
    p_group_id UUID,
    p_token TEXT DEFAULT NULL,
    p_source join_request_source DEFAULT NULL,
    p_answers JSONB DEFAULT '[]'::JSONB
)
RETURNS UUID AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_request_id UUID;
    v_invite_id UUID;
    v_token_hash TEXT;
    v_answer JSONB;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    PERFORM 1 FROM groups
    WHERE id = p_group_id AND is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Group not found or deleted';
    END IF;

    IF NOT fn_validate_join_eligibility(v_caller, p_group_id) THEN
        RAISE EXCEPTION 'Gender policy does not allow joining this group';
    END IF;

    PERFORM 1 FROM group_memberships
    WHERE group_id = p_group_id
      AND user_id = v_caller
      AND status = 'ACTIVE';

    IF FOUND THEN
        RAISE EXCEPTION 'Already a member of this group';
    END IF;

    PERFORM 1 FROM group_join_requests
    WHERE group_id = p_group_id
      AND requester_user_id = v_caller
      AND status = 'PENDING';

    IF FOUND THEN
        RAISE EXCEPTION 'Already have a pending request for this group';
    END IF;

    IF p_token IS NOT NULL THEN
        v_token_hash := encode(digest(p_token, 'sha256'), 'hex');

        SELECT gi.id INTO v_invite_id
        FROM group_invites gi
        WHERE gi.token_hash = v_token_hash
          AND gi.group_id = p_group_id
          AND gi.revoked_at IS NULL
          AND (gi.expires_at IS NULL OR gi.expires_at > now())
          AND (gi.max_uses IS NULL OR gi.use_count < gi.max_uses);

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Invite link is invalid, expired, or revoked';
        END IF;

        UPDATE group_invites SET use_count = use_count + 1
        WHERE id = v_invite_id;
    END IF;

    INSERT INTO group_join_requests (
        group_id, requester_user_id, status, source, invite_id
    ) VALUES (
        p_group_id, v_caller, 'PENDING',
        COALESCE(p_source, CASE WHEN p_token IS NOT NULL THEN 'INVITE_LINK'::join_request_source ELSE NULL END),
        v_invite_id
    )
    RETURNING id INTO v_request_id;

    FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers)
    LOOP
        INSERT INTO group_join_request_answers (
            join_request_id, question_id, question_version, answer_text
        ) VALUES (
            v_request_id,
            (v_answer->>'question_id')::UUID,
            COALESCE((v_answer->>'question_version')::INT, 1),
            v_answer->>'answer_text'
        );
    END LOOP;

    RETURN v_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions;


-- ============================================================
-- fn_pending_join_requests_for_me
-- ============================================================
-- Returns pending join requests across all groups where the
-- caller is an ACTIVE member. Pre-aggregates approval count,
-- quorum, and whether the caller has already voted.
--
-- SECURITY DEFINER: must filter to caller's groups explicitly —
-- RLS is bypassed.

CREATE OR REPLACE FUNCTION fn_pending_join_requests_for_me()
RETURNS TABLE (
    id UUID,
    group_id UUID,
    group_name TEXT,
    created_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ,
    approval_count BIGINT,
    quorum INT,
    i_have_voted BOOLEAN,
    answers JSONB
) AS $$
DECLARE
    v_caller UUID := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT
        jr.id,
        jr.group_id,
        g.name,
        jr.created_at,
        jr.expires_at,

        (SELECT COUNT(*) FROM group_join_votes jv
         WHERE jv.join_request_id = jr.id
           AND jv.vote = 'APPROVE')::BIGINT,

        CASE
            WHEN g.member_count < COALESCE((g.settings->>'democraticThreshold')::INT, 10)
            THEN GREATEST(COALESCE((g.settings->>'memberApproverQuorum')::INT, 2), 2)
            ELSE COALESCE((g.settings->>'memberApproverQuorum')::INT, 2)
        END,

        EXISTS (
            SELECT 1 FROM group_join_votes jv
            WHERE jv.join_request_id = jr.id
              AND jv.voter_user_id = v_caller
        ),

        COALESCE(
            (SELECT jsonb_agg(jsonb_build_object(
                'question_id', a.question_id,
                'prompt', eq.prompt,
                'answer_text', a.answer_text
            ) ORDER BY eq.sort_order)
            FROM group_join_request_answers a
            JOIN group_entry_questions eq ON eq.id = a.question_id
            WHERE a.join_request_id = jr.id),
            '[]'::JSONB
        )

    FROM group_join_requests jr
    JOIN groups g ON g.id = jr.group_id AND g.is_deleted = FALSE
    WHERE jr.status = 'PENDING'
      AND jr.expires_at > now()
      AND EXISTS (
          SELECT 1 FROM group_memberships gm
          WHERE gm.group_id = jr.group_id
            AND gm.user_id = v_caller
            AND gm.status = 'ACTIVE'
      )
    ORDER BY jr.created_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
