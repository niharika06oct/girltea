-- ============================================================
-- GirlTea App — Triggers
-- ============================================================
-- Suggestion incorporated: member_count maintained via trigger
-- for race-condition-safe transactional updates.

-- ---- Auto-update member_count on groups ----

CREATE OR REPLACE FUNCTION fn_update_group_member_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'ACTIVE' THEN
        UPDATE groups SET member_count = member_count + 1,
                          updated_at = now()
        WHERE id = NEW.group_id;

    ELSIF TG_OP = 'DELETE' AND OLD.status = 'ACTIVE' THEN
        UPDATE groups SET member_count = GREATEST(member_count - 1, 0),
                          updated_at = now()
        WHERE id = OLD.group_id;

    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status != 'ACTIVE' AND NEW.status = 'ACTIVE' THEN
            UPDATE groups SET member_count = member_count + 1,
                              updated_at = now()
            WHERE id = NEW.group_id;
        ELSIF OLD.status = 'ACTIVE' AND NEW.status != 'ACTIVE' THEN
            UPDATE groups SET member_count = GREATEST(member_count - 1, 0),
                              updated_at = now()
            WHERE id = NEW.group_id;
        END IF;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_group_member_count
AFTER INSERT OR UPDATE OR DELETE ON group_memberships
FOR EACH ROW EXECUTE FUNCTION fn_update_group_member_count();


-- ---- Auto-set updated_at timestamps ----

CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_groups_updated_at
BEFORE UPDATE ON groups
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_posts_updated_at
BEFORE UPDATE ON posts
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_comments_updated_at
BEFORE UPDATE ON comments
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();

CREATE TRIGGER trg_entry_questions_updated_at
BEFORE UPDATE ON group_entry_questions
FOR EACH ROW EXECUTE FUNCTION fn_set_updated_at();


-- ---- Auto-expire stale join requests ----
-- This would typically run as a scheduled job (pg_cron or app-level),
-- but here is the function it would call:

CREATE OR REPLACE FUNCTION fn_expire_stale_join_requests()
RETURNS INT AS $$
DECLARE
    affected INT;
BEGIN
    UPDATE group_join_requests
    SET status = 'EXPIRED',
        resolved_at = now()
    WHERE status = 'PENDING'
      AND expires_at < now();

    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN affected;
END;
$$ LANGUAGE plpgsql;
