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


-- ---- Column-lock: reject changes to immutable fields on posts ----
-- FIX #3: Without this, an author can rewrite author_alias to
-- attribute their words to another member, or move group_id to
-- drop a post into a room they're not in.

CREATE OR REPLACE FUNCTION fn_lock_post_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.author_user_id != OLD.author_user_id THEN
        RAISE EXCEPTION 'Cannot change post author';
    END IF;
    IF NEW.author_alias != OLD.author_alias THEN
        RAISE EXCEPTION 'Cannot change post alias';
    END IF;
    IF NEW.group_id != OLD.group_id THEN
        RAISE EXCEPTION 'Cannot move post to another group';
    END IF;
    IF NEW.type != OLD.type THEN
        RAISE EXCEPTION 'Cannot change post type';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_lock_post_columns
BEFORE UPDATE ON posts
FOR EACH ROW EXECUTE FUNCTION fn_lock_post_columns();


-- ---- Column-lock: reject changes to immutable fields on comments ----

CREATE OR REPLACE FUNCTION fn_lock_comment_columns()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.author_user_id != OLD.author_user_id THEN
        RAISE EXCEPTION 'Cannot change comment author';
    END IF;
    IF NEW.author_alias != OLD.author_alias THEN
        RAISE EXCEPTION 'Cannot change comment alias';
    END IF;
    IF NEW.post_id != OLD.post_id THEN
        RAISE EXCEPTION 'Cannot move comment to another post';
    END IF;
    IF NEW.type != OLD.type THEN
        RAISE EXCEPTION 'Cannot change comment type';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_lock_comment_columns
BEFORE UPDATE ON comments
FOR EACH ROW EXECUTE FUNCTION fn_lock_comment_columns();


-- ---- Auto-update upvote_count on posts ----

CREATE OR REPLACE FUNCTION fn_update_post_upvote_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE posts SET upvote_count = upvote_count + 1
        WHERE id = NEW.post_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE posts SET upvote_count = GREATEST(upvote_count - 1, 0)
        WHERE id = OLD.post_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_post_upvote_count
AFTER INSERT OR DELETE ON post_upvotes
FOR EACH ROW EXECUTE FUNCTION fn_update_post_upvote_count();


-- ---- Auto-expire stale requests ----
-- Typically run as a scheduled job (pg_cron or app-level).

CREATE OR REPLACE FUNCTION fn_expire_stale_requests()
RETURNS TABLE (expired_join INT, expired_removal INT) AS $$
DECLARE
    v_join INT;
    v_removal INT;
BEGIN
    UPDATE group_join_requests
    SET status = 'EXPIRED',
        resolved_at = now()
    WHERE status = 'PENDING'
      AND expires_at < now();
    GET DIAGNOSTICS v_join = ROW_COUNT;

    UPDATE group_removal_requests
    SET status = 'EXPIRED',
        resolved_at = now()
    WHERE status = 'PENDING'
      AND expires_at < now();
    GET DIAGNOSTICS v_removal = ROW_COUNT;

    RETURN QUERY SELECT v_join, v_removal;
END;
$$ LANGUAGE plpgsql;
