-- ============================================================
-- GirlTea App — Democratic Removal Logic
-- ============================================================
-- No single person can remove another. Any member raises a
-- request; a second member must approve. For groups above
-- democraticThreshold, removalQuorum (from settings) applies.
--
-- FIX #3: Rejection quorum implemented — same threshold as approval.
-- FIX #4: OWNER cannot be removed. Ownership must be transferred first.

CREATE OR REPLACE FUNCTION fn_cast_removal_vote(
    p_removal_request_id UUID,
    p_vote vote_decision
)
RETURNS TABLE (
    request_status removal_request_status,
    approval_count INT,
    rejection_count INT,
    quorum_required INT
) AS $$
DECLARE
    p_voter_user_id UUID := auth.uid();
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
    v_current_rejections INT;
BEGIN
    IF p_voter_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

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
    WHERE g.id = v_group_id
      AND g.is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Group not found or deleted';
    END IF;

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

    SELECT COUNT(*) INTO v_current_rejections
    FROM group_removal_votes rv
    WHERE rv.removal_request_id = p_removal_request_id
      AND rv.vote = 'REJECT';

    -- FIX #3: Rejection quorum
    IF p_vote = 'REJECT' AND v_current_rejections >= v_quorum THEN
        UPDATE group_removal_requests
        SET status = 'REJECTED', resolved_at = now()
        WHERE id = p_removal_request_id;

        RETURN QUERY SELECT 'REJECTED'::removal_request_status,
                            v_current_approvals,
                            v_current_rejections,
                            v_quorum;
        RETURN;
    END IF;

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
                            v_current_rejections,
                            v_quorum;
    ELSE
        RETURN QUERY SELECT 'PENDING'::removal_request_status,
                            v_current_approvals,
                            v_current_rejections,
                            v_quorum;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_raise_removal_request
-- ============================================================
-- FIX #4: Cannot target OWNER. Ownership must be transferred first.
-- FIX #6: Catches the partial unique constraint and raises a
-- readable error instead of raw constraint violation.
-- FIX #7: Two-member groups — quorum is 2 but only 1 eligible
-- voter (target is blocked). Function raises a clear message.

CREATE OR REPLACE FUNCTION fn_raise_removal_request(
    p_group_id UUID,
    p_target_alias TEXT,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_target_user_id UUID;
    v_target_role membership_role;
    v_request_id UUID;
    v_requester_role membership_role;
    v_settings JSONB;
    v_ttl_hours INT;
    v_member_count INT;
    v_quorum INT;
    v_eligible_voters INT;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT g.settings, g.member_count
    INTO v_settings, v_member_count
    FROM groups g
    WHERE g.id = p_group_id AND g.is_deleted = FALSE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Group not found or deleted';
    END IF;

    SELECT gm.role INTO v_requester_role
    FROM group_memberships gm
    WHERE gm.group_id = p_group_id
      AND gm.user_id = v_caller
      AND gm.status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Requester is not an active member of the group';
    END IF;

    SELECT gm.user_id, gm.role INTO v_target_user_id, v_target_role
    FROM group_memberships gm
    WHERE gm.group_id = p_group_id
      AND gm.alias = p_target_alias
      AND gm.status = 'ACTIVE';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'No active member with that alias in this group';
    END IF;

    IF v_caller = v_target_user_id THEN
        RAISE EXCEPTION 'Cannot request removal of yourself';
    END IF;

    -- FIX #4: Block OWNER removal
    IF v_target_role = 'OWNER' THEN
        RAISE EXCEPTION 'Cannot remove the group owner. Ownership must be transferred first.';
    END IF;

    -- FIX #7: Check if removal is even possible given member count
    v_quorum := COALESCE((v_settings->>'removalQuorum')::INT, 2);
    IF v_member_count < COALESCE((v_settings->>'democraticThreshold')::INT, 10) THEN
        v_quorum := 2;
    END IF;

    v_eligible_voters := v_member_count - 1;
    IF v_eligible_voters < v_quorum THEN
        RAISE EXCEPTION 'Not enough members to reach removal quorum (need %, have % eligible). '
            'In a 2-member group, removal is not possible — the other person can leave voluntarily.',
            v_quorum, v_eligible_voters;
    END IF;

    v_ttl_hours := COALESCE((v_settings->>'removalRequestTtlHours')::INT, 168);

    BEGIN
        INSERT INTO group_removal_requests (
            group_id, target_user_id, requested_by_user_id, reason, expires_at
        ) VALUES (
            p_group_id, v_target_user_id, v_caller, p_reason,
            now() + (v_ttl_hours || ' hours')::INTERVAL
        )
        RETURNING id INTO v_request_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'A pending removal request already exists for this member';
    END;

    INSERT INTO group_removal_votes (removal_request_id, voter_user_id, vote, voter_role)
    VALUES (v_request_id, v_caller, 'APPROVE', v_requester_role);

    RETURN v_request_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

REVOKE EXECUTE ON FUNCTION fn_cast_removal_vote(UUID, vote_decision) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_raise_removal_request(UUID, TEXT, TEXT) FROM anon;
