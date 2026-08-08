-- ============================================================
-- GirlTea App — Moderation RPCs
-- ============================================================
-- Reports are filed and moderated through SECURITY DEFINER RPCs so
-- that: evidence is snapshotted at report time, only a group's
-- OWNER/ADMIN can moderate its content, and every moderator action
-- lands in the append-only report_actions log.
--
-- Moderator model: for MVP, the group's OWNER/ADMIN moderates reports
-- scoped to that group. A platform-wide moderator table can layer on
-- later without changing these signatures.
--
-- Requires: fn_is_group_member / fn_is_group_owner (auth_helpers.sql).

-- ============================================================
-- fn_is_group_moderator: OWNER or ADMIN of the group
-- ============================================================

CREATE OR REPLACE FUNCTION fn_is_group_moderator(p_group_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    IF auth.uid() IS NULL OR p_group_id IS NULL THEN
        RETURN FALSE;
    END IF;

    RETURN EXISTS (
        SELECT 1 FROM group_memberships
        WHERE group_id = p_group_id
          AND user_id = auth.uid()
          AND role IN ('OWNER', 'ADMIN')
          AND status = 'ACTIVE'
    );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_resolve_report_group: which group does a target belong to?
-- ============================================================
-- Best-effort. NULL for USER targets or unresolvable ids.

CREATE OR REPLACE FUNCTION fn_resolve_report_group(
    p_target_type report_target_type,
    p_target_id UUID
)
RETURNS UUID AS $$
DECLARE
    v_group_id UUID;
BEGIN
    CASE p_target_type
        WHEN 'POST' THEN
            SELECT group_id INTO v_group_id FROM posts WHERE id = p_target_id;
        WHEN 'COMMENT' THEN
            SELECT p.group_id INTO v_group_id
            FROM comments c JOIN posts p ON p.id = c.post_id
            WHERE c.id = p_target_id;
        WHEN 'GROUP' THEN
            v_group_id := p_target_id;
        WHEN 'USER' THEN
            v_group_id := NULL;
    END CASE;

    RETURN v_group_id;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_submit_report: file a report, snapshotting evidence
-- ============================================================
-- The reporter must be a member of the target's group (you can only
-- report content you can see). Evidence (body/media/author snapshot)
-- is frozen now, before the content can be edited or soft-deleted.

CREATE OR REPLACE FUNCTION fn_submit_report(
    p_target_type report_target_type,
    p_target_id UUID,
    p_reason report_reason,
    p_details TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_group_id UUID;
    v_evidence JSONB := '{}'::jsonb;
    v_report_id UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    v_group_id := fn_resolve_report_group(p_target_type, p_target_id);

    -- For group-scoped targets, the reporter must be a member (can't
    -- report into a room you can't see). USER reports with no group
    -- context are allowed through.
    IF v_group_id IS NOT NULL AND NOT fn_is_group_member(v_group_id) THEN
        RAISE EXCEPTION 'You are not a member of the group this content belongs to';
    END IF;

    -- Snapshot evidence at report time.
    CASE p_target_type
        WHEN 'POST' THEN
            SELECT jsonb_build_object(
                'type', p.type, 'body', p.body, 'media_url', p.media_url,
                'author_alias', p.author_alias, 'created_at', p.created_at,
                'is_deleted', p.is_deleted
            ) INTO v_evidence
            FROM posts p WHERE p.id = p_target_id;
        WHEN 'COMMENT' THEN
            SELECT jsonb_build_object(
                'type', c.type, 'body', c.body, 'media_url', c.media_url,
                'author_alias', c.author_alias, 'post_id', c.post_id,
                'created_at', c.created_at, 'is_deleted', c.is_deleted
            ) INTO v_evidence
            FROM comments c WHERE c.id = p_target_id;
        WHEN 'GROUP' THEN
            SELECT jsonb_build_object(
                'name', g.name, 'description', g.description, 'policy', g.policy
            ) INTO v_evidence
            FROM groups g WHERE g.id = p_target_id;
        WHEN 'USER' THEN
            v_evidence := '{}'::jsonb;
    END CASE;

    IF v_evidence IS NULL THEN
        RAISE EXCEPTION 'Reported % not found', p_target_type;
    END IF;

    INSERT INTO reports (
        target_type, target_id, group_id, reporter_user_id,
        reason, details, evidence, status
    ) VALUES (
        p_target_type, p_target_id, v_group_id, v_caller,
        p_reason, p_details, v_evidence, 'PENDING'
    )
    RETURNING id INTO v_report_id;

    RETURN v_report_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_assign_report: moderator picks up a report
-- ============================================================

CREATE OR REPLACE FUNCTION fn_assign_report(p_report_id UUID)
RETURNS VOID AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_group_id UUID;
    v_status report_status;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT group_id, status INTO v_group_id, v_status
    FROM reports WHERE id = p_report_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report not found';
    END IF;
    IF v_group_id IS NULL OR NOT fn_is_group_moderator(v_group_id) THEN
        RAISE EXCEPTION 'Only a group moderator can act on this report';
    END IF;
    IF v_status NOT IN ('PENDING', 'UNDER_REVIEW') THEN
        RAISE EXCEPTION 'Report is already resolved (%).', v_status;
    END IF;

    UPDATE reports
    SET status = 'UNDER_REVIEW', assigned_to_user_id = v_caller
    WHERE id = p_report_id;

    INSERT INTO report_actions (report_id, actor_user_id, action, note)
    VALUES (p_report_id, v_caller, 'ASSIGNED', NULL);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_action_report: record a moderation decision
-- ============================================================
-- Logs the action, applies the content/user effect where applicable,
-- and moves the report to a terminal status for ACTIONED/DISMISSED.
-- CONTENT_REMOVED soft-deletes the target; USER_BANNED bans the target
-- author's membership in the report's group.

CREATE OR REPLACE FUNCTION fn_action_report(
    p_report_id UUID,
    p_action moderation_action,
    p_note TEXT DEFAULT NULL
)
RETURNS report_status AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_group_id UUID;
    v_target_type report_target_type;
    v_target_id UUID;
    v_status report_status;
    v_new_status report_status;
    v_author UUID;
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT group_id, target_type, target_id, status
    INTO v_group_id, v_target_type, v_target_id, v_status
    FROM reports WHERE id = p_report_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report not found';
    END IF;
    IF v_group_id IS NULL OR NOT fn_is_group_moderator(v_group_id) THEN
        RAISE EXCEPTION 'Only a group moderator can act on this report';
    END IF;
    IF v_status IN ('ACTIONED', 'DISMISSED') THEN
        RAISE EXCEPTION 'Report is already resolved (%).', v_status;
    END IF;

    -- Apply the effect of the action.
    CASE p_action
        WHEN 'CONTENT_REMOVED' THEN
            IF v_target_type = 'POST' THEN
                UPDATE posts SET is_deleted = TRUE, deleted_at = now()
                WHERE id = v_target_id AND is_deleted = FALSE;
            ELSIF v_target_type = 'COMMENT' THEN
                UPDATE comments SET is_deleted = TRUE, deleted_at = now()
                WHERE id = v_target_id AND is_deleted = FALSE;
            END IF;
            v_new_status := 'ACTIONED';

        WHEN 'USER_BANNED' THEN
            -- Resolve the author of the reported content, ban in this group.
            IF v_target_type = 'POST' THEN
                SELECT author_user_id INTO v_author FROM posts WHERE id = v_target_id;
            ELSIF v_target_type = 'COMMENT' THEN
                SELECT author_user_id INTO v_author FROM comments WHERE id = v_target_id;
            ELSIF v_target_type = 'USER' THEN
                v_author := v_target_id;
            END IF;

            IF v_author IS NOT NULL AND v_group_id IS NOT NULL THEN
                UPDATE group_memberships
                SET status = 'BANNED', updated_at = now()
                WHERE group_id = v_group_id AND user_id = v_author
                  AND role <> 'OWNER';   -- never ban the owner via a report
            END IF;
            v_new_status := 'ACTIONED';

        WHEN 'CONTENT_KEPT', 'DISMISSED' THEN
            v_new_status := 'DISMISSED';

        WHEN 'USER_WARNED', 'ESCALATED', 'NOTE', 'ASSIGNED' THEN
            -- Non-terminal: log it, keep the report under review.
            v_new_status := 'UNDER_REVIEW';
    END CASE;

    UPDATE reports
    SET status = v_new_status,
        assigned_to_user_id = COALESCE(assigned_to_user_id, v_caller),
        resolution_note = CASE WHEN v_new_status IN ('ACTIONED', 'DISMISSED')
                               THEN COALESCE(p_note, resolution_note) ELSE resolution_note END,
        resolved_at = CASE WHEN v_new_status IN ('ACTIONED', 'DISMISSED')
                           THEN now() ELSE resolved_at END
    WHERE id = p_report_id;

    INSERT INTO report_actions (report_id, actor_user_id, action, note)
    VALUES (p_report_id, v_caller, p_action, p_note);

    RETURN v_new_status;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_moderation_queue: open reports for groups I moderate
-- ============================================================

CREATE OR REPLACE FUNCTION fn_moderation_queue()
RETURNS TABLE (
    id UUID,
    group_id UUID,
    target_type report_target_type,
    target_id UUID,
    reason report_reason,
    details TEXT,
    evidence JSONB,
    status report_status,
    assigned_to_me BOOLEAN,
    created_at TIMESTAMPTZ
) AS $$
DECLARE
    v_caller UUID := auth.uid();
BEGIN
    IF v_caller IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN QUERY
    SELECT r.id, r.group_id, r.target_type, r.target_id, r.reason,
           r.details, r.evidence, r.status,
           (r.assigned_to_user_id = v_caller),
           r.created_at
    FROM reports r
    WHERE r.status IN ('PENDING', 'UNDER_REVIEW')
      AND r.group_id IS NOT NULL
      AND fn_is_group_moderator(r.group_id)
    ORDER BY r.created_at;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- REVOKE EXECUTE from anon
-- ============================================================

REVOKE EXECUTE ON FUNCTION fn_is_group_moderator(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_resolve_report_group(report_target_type, UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_submit_report(report_target_type, UUID, report_reason, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_assign_report(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_action_report(UUID, moderation_action, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_moderation_queue() FROM anon;
