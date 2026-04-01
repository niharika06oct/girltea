-- ============================================================
-- GirlTea App — Approval Transaction Logic
-- ============================================================
-- Suggestion incorporated: wrap "cast vote → maybe admit" in a
-- single database transaction so two simultaneous last votes
-- don't double-insert a membership.
--
-- This function is called when a member/admin votes on a join
-- request. It atomically: records the vote, checks if quorum
-- is met, and if so admits the requester.

CREATE OR REPLACE FUNCTION fn_cast_join_vote(
    p_join_request_id UUID,
    p_voter_user_id UUID,
    p_vote vote_decision
)
RETURNS TABLE (
    request_status join_request_status,
    approval_count INT,
    quorum_required INT
) AS $$
DECLARE
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
BEGIN
    -- Lock the join request row to prevent concurrent vote races
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

    -- Verify voter is an active member of the group and get their role
    SELECT gm.role INTO v_voter_role
    FROM group_memberships gm
    WHERE gm.group_id = v_group_id
      AND gm.user_id = p_voter_user_id
      AND gm.status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voter is not an active member of the group';
    END IF;

    -- Get group settings to determine approval rules
    SELECT g.settings, g.member_count, g.policy
    INTO v_settings, v_member_count, v_group_policy
    FROM groups g
    WHERE g.id = v_group_id;

    v_quorum := COALESCE((v_settings->>'memberApproverQuorum')::INT, 2);
    v_approval_mode := COALESCE(v_settings->>'approvalMode', 'HYBRID');
    v_max_size := COALESCE((v_settings->>'memberApprovalMaxGroupSize')::INT, 20);

    -- Enforce approval mode: if ADMINS_ONLY or HYBRID with large group,
    -- only OWNER/ADMIN can vote
    IF v_approval_mode = 'ADMINS_ONLY'
       OR (v_approval_mode = 'HYBRID' AND v_member_count >= v_max_size) THEN
        IF v_voter_role NOT IN ('OWNER', 'ADMIN') THEN
            RAISE EXCEPTION 'Only admins can approve in this group (mode: %, size: %)',
                v_approval_mode, v_member_count;
        END IF;
    END IF;

    -- Record the vote (unique constraint prevents double-voting)
    INSERT INTO group_join_votes (join_request_id, voter_user_id, vote, voter_role)
    VALUES (p_join_request_id, p_voter_user_id, p_vote, v_voter_role);

    -- Check if we've reached quorum for approval
    SELECT COUNT(*) INTO v_current_approvals
    FROM group_join_votes jv
    WHERE jv.join_request_id = p_join_request_id
      AND jv.vote = 'APPROVE';

    IF p_vote = 'APPROVE' AND v_current_approvals >= v_quorum THEN
        -- Admit the requester
        UPDATE group_join_requests
        SET status = 'APPROVED', resolved_at = now()
        WHERE id = p_join_request_id;

        INSERT INTO group_memberships (group_id, user_id, role, status)
        VALUES (v_group_id, v_requester_id, 'MEMBER', 'ACTIVE')
        ON CONFLICT (group_id, user_id) DO UPDATE
            SET status = 'ACTIVE', joined_at = now(), updated_at = now();

        RETURN QUERY SELECT 'APPROVED'::join_request_status,
                            v_current_approvals,
                            v_quorum;
    ELSE
        RETURN QUERY SELECT 'PENDING'::join_request_status,
                            v_current_approvals,
                            v_quorum;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- Policy validation: check gender eligibility before join request
-- ============================================================

CREATE OR REPLACE FUNCTION fn_validate_join_eligibility(
    p_user_id UUID,
    p_group_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_policy group_policy;
    v_user_gender gender;
    v_visibility group_visibility;
BEGIN
    SELECT g.policy, g.visibility INTO v_policy, v_visibility
    FROM groups g WHERE g.id = p_group_id AND g.is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Group not found or deleted';
    END IF;

    SELECT u.gender INTO v_user_gender
    FROM users u WHERE u.id = p_user_id AND u.is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found or deleted';
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
            NULL; -- no gender requirement
    END CASE;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;
