-- ============================================================
-- GirlTea App — Democratic Removal Logic
-- ============================================================
-- No single person can remove another. Any member raises a
-- request; a second member must approve. For groups above
-- democraticThreshold, removalQuorum (from settings) applies.
-- The requester's intent counts as the first APPROVE vote
-- automatically.

CREATE OR REPLACE FUNCTION fn_cast_removal_vote(
    p_removal_request_id UUID,
    p_voter_user_id UUID,
    p_vote vote_decision
)
RETURNS TABLE (
    request_status removal_request_status,
    approval_count INT,
    quorum_required INT
) AS $$
DECLARE
    v_group_id UUID;
    v_target_user_id UUID;
    v_requested_by UUID;
    v_request_status removal_request_status;
    v_member_count INT;
    v_settings JSONB;
    v_voter_role membership_role;
    v_quorum INT;
    v_democratic_threshold INT;
    v_current_approvals INT;
BEGIN
    SELECT rr.group_id, rr.target_user_id, rr.requested_by_user_id, rr.status
    INTO v_group_id, v_target_user_id, v_requested_by, v_request_status
    FROM group_removal_requests rr
    WHERE rr.id = p_removal_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Removal request not found: %', p_removal_request_id;
    END IF;

    IF v_request_status != 'PENDING' THEN
        RAISE EXCEPTION 'Removal request is not pending (current: %)', v_request_status;
    END IF;

    IF p_voter_user_id = v_target_user_id THEN
        RAISE EXCEPTION 'Target of removal cannot vote on their own removal';
    END IF;

    SELECT gm.role INTO v_voter_role
    FROM group_memberships gm
    WHERE gm.group_id = v_group_id
      AND gm.user_id = p_voter_user_id
      AND gm.status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Voter is not an active member of the group';
    END IF;

    SELECT g.settings, g.member_count
    INTO v_settings, v_member_count
    FROM groups g
    WHERE g.id = v_group_id;

    v_democratic_threshold := COALESCE((v_settings->>'democraticThreshold')::INT, 10);
    v_quorum := COALESCE((v_settings->>'removalQuorum')::INT, 2);

    IF v_member_count < v_democratic_threshold THEN
        v_quorum := 2;
    END IF;

    INSERT INTO group_removal_votes (removal_request_id, voter_user_id, vote, voter_role)
    VALUES (p_removal_request_id, p_voter_user_id, p_vote, v_voter_role);

    SELECT COUNT(*) INTO v_current_approvals
    FROM group_removal_votes rv
    WHERE rv.removal_request_id = p_removal_request_id
      AND rv.vote = 'APPROVE';

    IF p_vote = 'APPROVE' AND v_current_approvals >= v_quorum THEN
        UPDATE group_removal_requests
        SET status = 'APPROVED', resolved_at = now()
        WHERE id = p_removal_request_id;

        UPDATE group_memberships
        SET status = 'BANNED', updated_at = now()
        WHERE group_id = v_group_id
          AND user_id = v_target_user_id;

        RETURN QUERY SELECT 'APPROVED'::removal_request_status,
                            v_current_approvals,
                            v_quorum;
    ELSE
        RETURN QUERY SELECT 'PENDING'::removal_request_status,
                            v_current_approvals,
                            v_quorum;
    END IF;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- Helper: raise a removal request (auto-records requester's
-- APPROVE vote so only 1 more person is needed for quorum of 2)
-- ============================================================

CREATE OR REPLACE FUNCTION fn_raise_removal_request(
    p_group_id UUID,
    p_requested_by_user_id UUID,
    p_target_user_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_request_id UUID;
    v_requester_role membership_role;
    v_settings JSONB;
    v_ttl_hours INT;
BEGIN
    IF p_requested_by_user_id = p_target_user_id THEN
        RAISE EXCEPTION 'Cannot request removal of yourself';
    END IF;

    SELECT gm.role INTO v_requester_role
    FROM group_memberships gm
    WHERE gm.group_id = p_group_id
      AND gm.user_id = p_requested_by_user_id
      AND gm.status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Requester is not an active member of the group';
    END IF;

    PERFORM 1 FROM group_memberships
    WHERE group_id = p_group_id
      AND user_id = p_target_user_id
      AND status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Target is not an active member of the group';
    END IF;

    SELECT g.settings INTO v_settings
    FROM groups g WHERE g.id = p_group_id;

    v_ttl_hours := COALESCE((v_settings->>'removalRequestTtlHours')::INT, 168);

    INSERT INTO group_removal_requests (
        group_id, target_user_id, requested_by_user_id, reason, expires_at
    ) VALUES (
        p_group_id, p_target_user_id, p_requested_by_user_id, p_reason,
        now() + (v_ttl_hours || ' hours')::INTERVAL
    )
    RETURNING id INTO v_request_id;

    INSERT INTO group_removal_votes (removal_request_id, voter_user_id, vote, voter_role)
    VALUES (v_request_id, p_requested_by_user_id, 'APPROVE', v_requester_role);

    RETURN v_request_id;
END;
$$ LANGUAGE plpgsql;
