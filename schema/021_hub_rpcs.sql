-- ============================================================
-- GirlTea App — Hub RPCs
-- ============================================================
-- All SECURITY DEFINER with locked search_path.
-- All derive caller from auth.uid().
-- Requires: pgcrypto extension (for digest()).

-- ============================================================
-- fn_create_group_with_owner
-- ============================================================
-- FIX #1: Validates caller's gender against the group policy
-- BEFORE creating the group. A man cannot create a WOMEN_ONLY
-- room even via raw RPC call.

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
    v_user_gender gender;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT u.gender INTO v_user_gender
    FROM users u
    WHERE u.id = v_caller AND u.is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found — complete onboarding first';
    END IF;

    CASE p_policy
        WHEN 'WOMEN_ONLY' THEN
            IF v_user_gender IS NULL OR v_user_gender != 'WOMAN' THEN
                RAISE EXCEPTION 'Only women can create a WOMEN_ONLY group';
            END IF;
        WHEN 'MIXED' THEN
            IF v_user_gender IS NULL THEN
                RAISE EXCEPTION 'Gender must be set to create a MIXED group';
            END IF;
        WHEN 'GENDER_NEUTRAL' THEN
            NULL;
    END CASE;

    INSERT INTO groups (name, description, policy, visibility, category_tags, created_by_user_id)
    VALUES (p_name, p_description, p_policy, p_visibility, p_category_tags, v_caller)
    RETURNING id INTO v_group_id;

    INSERT INTO group_memberships (group_id, user_id, role, status, alias)
    VALUES (v_group_id, v_caller, 'OWNER', 'ACTIVE', fn_generate_alias_for_group(v_group_id));

    RETURN v_group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_resolve_invite
-- ============================================================
-- Accepts raw token, hashes internally, returns ONLY safe metadata.
-- Never returns member list or posts.

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
-- FIX #2: Validates that every required entry question for the
-- group has a non-blank answer, and that every submitted
-- question_id belongs to p_group_id.
--
-- FIX #5: Does NOT increment invite use_count here. use_count
-- is incremented in fn_cast_join_vote on admission, so a
-- rejected/expired request doesn't burn the invite.

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
    v_required_question RECORD;
    v_submitted_qid UUID;
    v_submitted_group UUID;
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

    -- FIX #2: Block BANNED users from re-requesting
    PERFORM 1 FROM group_memberships
    WHERE group_id = p_group_id
      AND user_id = v_caller
      AND status = 'BANNED';

    IF FOUND THEN
        RAISE EXCEPTION 'You are banned from this group';
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

    -- Validate every submitted question_id belongs to this group
    FOR v_answer IN SELECT * FROM jsonb_array_elements(p_answers)
    LOOP
        v_submitted_qid := (v_answer->>'question_id')::UUID;

        SELECT eq.group_id INTO v_submitted_group
        FROM group_entry_questions eq
        WHERE eq.id = v_submitted_qid;

        IF NOT FOUND OR v_submitted_group != p_group_id THEN
            RAISE EXCEPTION 'Question % does not belong to this group', v_submitted_qid;
        END IF;

        IF COALESCE(TRIM(v_answer->>'answer_text'), '') = '' THEN
            RAISE EXCEPTION 'Answer for question % is blank', v_submitted_qid;
        END IF;
    END LOOP;

    -- Validate every required question has an answer
    FOR v_required_question IN
        SELECT eq.id FROM group_entry_questions eq
        WHERE eq.group_id = p_group_id AND eq.is_required = TRUE
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_answers) a
            WHERE (a->>'question_id')::UUID = v_required_question.id
              AND COALESCE(TRIM(a->>'answer_text'), '') != ''
        ) THEN
            RAISE EXCEPTION 'Required question % is not answered', v_required_question.id;
        END IF;
    END LOOP;

    -- Validate invite token if provided (but don't consume use_count yet)
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
-- FIX #6: Adds i_can_vote based on approvalMode. For ADMINS_ONLY
-- groups above democraticThreshold, regular members see the
-- request but can't vote.

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
    i_can_vote BOOLEAN,
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

        CASE
            WHEN g.member_count < COALESCE((g.settings->>'democraticThreshold')::INT, 10)
            THEN TRUE
            WHEN COALESCE(g.settings->>'approvalMode', 'HYBRID') = 'MEMBERS_QUORUM'
            THEN TRUE
            WHEN COALESCE(g.settings->>'approvalMode', 'HYBRID') = 'ADMINS_ONLY'
            THEN EXISTS (
                SELECT 1 FROM group_memberships gm2
                WHERE gm2.group_id = jr.group_id
                  AND gm2.user_id = v_caller
                  AND gm2.status = 'ACTIVE'
                  AND gm2.role IN ('OWNER', 'ADMIN')
            )
            WHEN COALESCE(g.settings->>'approvalMode', 'HYBRID') = 'HYBRID'
                 AND g.member_count >= COALESCE((g.settings->>'memberApprovalMaxGroupSize')::INT, 20)
            THEN EXISTS (
                SELECT 1 FROM group_memberships gm2
                WHERE gm2.group_id = jr.group_id
                  AND gm2.user_id = v_caller
                  AND gm2.status = 'ACTIVE'
                  AND gm2.role IN ('OWNER', 'ADMIN')
            )
            ELSE TRUE
        END,

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


-- ============================================================
-- REVOKE EXECUTE from anon on all RPCs
-- ============================================================

REVOKE EXECUTE ON FUNCTION fn_create_group_with_owner(TEXT, TEXT, group_policy, group_visibility, TEXT[]) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_resolve_invite(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_submit_join_request(UUID, TEXT, join_request_source, JSONB) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_pending_join_requests_for_me() FROM anon;
