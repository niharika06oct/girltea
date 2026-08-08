-- ============================================================
-- GirlTea App — Approval Transaction Logic
-- ============================================================
-- Atomically: vote → check quorum → admit or reject.
-- SECURITY DEFINER: bypasses RLS, re-checks everything internally.
--
-- RAISE EXCEPTION rolls back the entire transaction including
-- any preceding UPDATEs. All rejection paths use RETURN instead,
-- so the status change commits.

CREATE OR REPLACE FUNCTION fn_cast_join_vote(
    p_join_request_id UUID,
    p_vote vote_decision
)
RETURNS TABLE (
    request_status join_request_status,
    approval_count INT,
    rejection_count INT,
    quorum_required INT
) AS $$
DECLARE
    p_voter_user_id UUID := auth.uid();
    v_group_id UUID;
    v_requester_id UUID;
    v_request_status join_request_status;
    v_group_policy group_policy;
    v_member_count INT;
    v_settings JSONB;
    v_voter_role membership_role;
    v_quorum INT;
    v_approval_mode TEXT;
    v_max_size INT;
    v_current_approvals INT;
    v_current_rejections INT;
    v_invite_rows INT;
    v_membership_rows INT;
    v_requester_gender gender;
BEGIN
    IF p_voter_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT jr.group_id, jr.requester_user_id, jr.status
    INTO v_group_id, v_requester_id, v_request_status
    FROM group_join_requests jr
    WHERE jr.id = p_join_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Join request not found: %', p_join_request_id;
    END IF;

    IF v_request_status != 'PENDING' THEN
        RAISE EXCEPTION 'Join request is not pending (current: %)', v_request_status;
    END IF;

    IF p_voter_user_id = v_requester_id THEN
        RAISE EXCEPTION 'Requester cannot vote on their own request';
    END IF;

    SELECT gm.role INTO v_voter_role
    FROM group_memberships gm
    WHERE gm.group_id = v_group_id
      AND gm.user_id = p_voter_user_id
      AND gm.status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voter is not an active member of the group';
    END IF;

    SELECT g.settings, g.member_count, g.policy
    INTO v_settings, v_member_count, v_group_policy
    FROM groups g
    WHERE g.id = v_group_id
      AND g.is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Group not found or deleted';
    END IF;

    v_approval_mode := COALESCE(v_settings->>'approvalMode', 'HYBRID');
    v_max_size := COALESCE((v_settings->>'memberApprovalMaxGroupSize')::INT, 20);

    IF v_member_count < COALESCE((v_settings->>'democraticThreshold')::INT, 10) THEN
        v_quorum := GREATEST(COALESCE((v_settings->>'memberApproverQuorum')::INT, 2), 2);
    ELSE
        v_quorum := COALESCE((v_settings->>'memberApproverQuorum')::INT, 2);

        IF v_approval_mode = 'ADMINS_ONLY'
           OR (v_approval_mode = 'HYBRID' AND v_member_count >= v_max_size) THEN
            IF v_voter_role NOT IN ('OWNER', 'ADMIN') THEN
                RAISE EXCEPTION 'Only admins can approve in this group (mode: %, size: %)',
                    v_approval_mode, v_member_count;
            END IF;
        END IF;
    END IF;

    INSERT INTO group_join_votes (join_request_id, voter_user_id, vote, voter_role)
    VALUES (p_join_request_id, p_voter_user_id, p_vote, v_voter_role);

    SELECT COUNT(*) INTO v_current_approvals
    FROM group_join_votes jv
    WHERE jv.join_request_id = p_join_request_id
      AND jv.vote = 'APPROVE';

    SELECT COUNT(*) INTO v_current_rejections
    FROM group_join_votes jv
    WHERE jv.join_request_id = p_join_request_id
      AND jv.vote = 'REJECT';

    -- Rejection quorum — same threshold as approval.
    IF p_vote = 'REJECT' AND v_current_rejections >= v_quorum THEN
        UPDATE group_join_requests
        SET status = 'REJECTED', resolved_at = now()
        WHERE id = p_join_request_id;

        RETURN QUERY SELECT 'REJECTED'::join_request_status,
                            v_current_approvals,
                            v_current_rejections,
                            v_quorum;
        RETURN;
    END IF;

    IF p_vote = 'APPROVE' AND v_current_approvals >= v_quorum THEN
        -- Re-check gender eligibility at admission time.
        -- Returns FALSE (not RAISE) for missing/ineligible user so
        -- the REJECTED status update commits.
        IF NOT fn_validate_join_eligibility(v_requester_id, v_group_id) THEN
            UPDATE group_join_requests
            SET status = 'REJECTED', resolved_at = now()
            WHERE id = p_join_request_id;

            RETURN QUERY SELECT 'REJECTED'::join_request_status,
                                v_current_approvals,
                                v_current_rejections,
                                v_quorum;
            RETURN;
        END IF;

        -- Block BANNED users. Return REJECTED (not RAISE) so it commits.
        PERFORM 1 FROM group_memberships
        WHERE group_id = v_group_id
          AND user_id = v_requester_id
          AND status = 'BANNED';

        IF FOUND THEN
            UPDATE group_join_requests
            SET status = 'REJECTED', resolved_at = now()
            WHERE id = p_join_request_id;

            RETURN QUERY SELECT 'REJECTED'::join_request_status,
                                v_current_approvals,
                                v_current_rejections,
                                v_quorum;
            RETURN;
        END IF;

        UPDATE group_join_requests
        SET status = 'APPROVED', resolved_at = now()
        WHERE id = p_join_request_id;

        -- Snapshot the requester's gender AS OF admission. This freezes
        -- the gender-policy guarantee onto the membership row so a later
        -- profile edit can't silently break it (see 004_group_memberships).
        SELECT u.gender INTO v_requester_gender
        FROM users u WHERE u.id = v_requester_id;

        INSERT INTO group_memberships (group_id, user_id, role, status, alias, gender_at_admission)
        VALUES (v_group_id, v_requester_id, 'MEMBER', 'ACTIVE', fn_generate_alias_for_group(v_group_id), v_requester_gender)
        ON CONFLICT (group_id, user_id) DO UPDATE
            SET status = 'ACTIVE', joined_at = now(), updated_at = now(),
                gender_at_admission = EXCLUDED.gender_at_admission
            WHERE group_memberships.status = 'LEFT';

        -- Check if membership was actually created/updated
        GET DIAGNOSTICS v_membership_rows = ROW_COUNT;
        IF v_membership_rows = 0 THEN
            UPDATE group_join_requests
            SET status = 'REJECTED', resolved_at = now()
            WHERE id = p_join_request_id;

            RETURN QUERY SELECT 'REJECTED'::join_request_status,
                                v_current_approvals,
                                v_current_rejections,
                                v_quorum;
            RETURN;
        END IF;

        -- Increment invite use_count on admission (race-safe).
        IF EXISTS (
            SELECT 1 FROM group_join_requests
            WHERE id = p_join_request_id AND invite_id IS NOT NULL
        ) THEN
            UPDATE group_invites
            SET use_count = use_count + 1
            WHERE id = (
                SELECT invite_id FROM group_join_requests
                WHERE id = p_join_request_id
            )
            AND (max_uses IS NULL OR use_count < max_uses);

            GET DIAGNOSTICS v_invite_rows = ROW_COUNT;
            IF v_invite_rows = 0 THEN
                RAISE WARNING 'Invite max_uses exceeded — admission proceeded but invite is exhausted';
            END IF;
        END IF;

        RETURN QUERY SELECT 'APPROVED'::join_request_status,
                            v_current_approvals,
                            v_current_rejections,
                            v_quorum;
    ELSE
        RETURN QUERY SELECT 'PENDING'::join_request_status,
                            v_current_approvals,
                            v_current_rejections,
                            v_quorum;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- Policy validation: check gender eligibility
-- ============================================================
-- Returns FALSE for missing/deleted users (not RAISE) so callers
-- can use the result without aborting their transaction.

CREATE OR REPLACE FUNCTION fn_validate_join_eligibility(
    p_user_id UUID,
    p_group_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_policy group_policy;
    v_user_gender gender;
BEGIN
    SELECT g.policy INTO v_policy
    FROM groups g WHERE g.id = p_group_id AND g.is_deleted = FALSE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    SELECT u.gender INTO v_user_gender
    FROM users u WHERE u.id = p_user_id AND u.is_deleted = FALSE;

    IF NOT FOUND THEN
        RETURN FALSE;
    END IF;

    CASE v_policy
        WHEN 'WOMEN_ONLY' THEN
            IF v_user_gender IS NULL OR v_user_gender != 'WOMAN' THEN
                RETURN FALSE;
            END IF;
        WHEN 'MIXED' THEN
            IF v_user_gender IS NULL THEN
                RETURN FALSE;
            END IF;
        WHEN 'GENDER_NEUTRAL' THEN
            NULL;
    END CASE;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION fn_cast_join_vote(UUID, vote_decision) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_validate_join_eligibility(UUID, UUID) FROM anon;
