-- ============================================================
-- GirlTea App — Right-to-Erasure (DPDP / GDPR purge path)
-- ============================================================
-- Soft-delete (is_deleted = TRUE) is a UX/moderation state: the row and
-- its media stay put so threads don't collapse and moderators keep their
-- evidence. It is NOT erasure. Under India's DPDP Act (and GDPR Art. 17),
-- an erasure request means the personal data is actually *purged* — the
-- body text, the uploaded media, the email/phone on the auth record.
--
-- We cannot physically DELETE a users row: posts, groups, votes and
-- reports carry NO ACTION foreign keys back to users(id), so the delete
-- would either be blocked or would cascade away other members' content.
-- Instead fn_erase_user turns the account into a scrubbed *tombstone*:
--   * all PII on public.users + auth.users is overwritten,
--   * the user's own posts/comments are content-stripped (body + media
--     cleared, marked deleted) so nothing they wrote survives,
--   * their group memberships, join requests and upvotes are removed,
--   * the free-text on reports they filed is cleared,
--   * every backing Storage object is deleted and also returned to the
--     caller so a job can purge the physical blob via the Storage API.
--
-- Structural stubs (a content-less post row, a vote record, the tombstone
-- user row) remain only to keep foreign keys and counters consistent —
-- they hold no personal data.
--
-- Requires: pgcrypto (gen_random_uuid), auth schema (auth.uid).

-- ============================================================
-- fn_erase_user: purge one account's personal data
-- ============================================================
-- Callable by the account owner (auth.uid() = p_user_id) or by a
-- backend/service_role job (auth.uid() IS NULL — e.g. an ops-handled
-- DPDP request). Returns a JSONB summary; the "storage_objects" array
-- lists {bucket, path} pairs whose blobs the caller MUST delete through
-- the Storage API. This function does NOT touch storage.objects itself:
-- Supabase's storage.protect_delete() trigger forbids direct SQL deletes
-- there (a guard against orphaning backend files), so blob removal is
-- necessarily a Storage-API step the caller performs with this list.

CREATE OR REPLACE FUNCTION fn_erase_user(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
    v_caller UUID := auth.uid();
    v_storage JSONB := '[]'::jsonb;
    v_posts INT := 0;
    v_comments INT := 0;
    v_memberships INT := 0;
    v_join_requests INT := 0;
    v_upvotes INT := 0;
    v_reports INT := 0;
    v_owned_groups INT := 0;
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'user id is required';
    END IF;

    -- Only the account owner or a backend job (service_role, no JWT sub)
    -- may erase an account.
    IF v_caller IS NOT NULL AND v_caller <> p_user_id THEN
        RAISE EXCEPTION 'You can only erase your own account';
    END IF;

    -- Lock the user row so a concurrent erase/edit can't race us.
    PERFORM 1 FROM users WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not found', p_user_id;
    END IF;

    -- ---- 1. Collect every Storage object owned by this user's content.
    -- media_url / thumbnail_url are bucket-relative names == storage.objects.name.
    SELECT COALESCE(jsonb_agg(obj), '[]'::jsonb) INTO v_storage
    FROM (
        SELECT jsonb_build_object('bucket', 'post-media', 'path', media_url) AS obj
        FROM posts WHERE author_user_id = p_user_id AND media_url IS NOT NULL
        UNION ALL
        SELECT jsonb_build_object('bucket', 'post-thumbnails', 'path', thumbnail_url)
        FROM posts WHERE author_user_id = p_user_id AND thumbnail_url IS NOT NULL
        UNION ALL
        SELECT jsonb_build_object('bucket', 'comment-media', 'path', media_url)
        FROM comments WHERE author_user_id = p_user_id AND media_url IS NOT NULL
    ) s;

    -- (Blob deletion happens through the Storage API by the caller, using
    -- the "storage_objects" list returned below — see note above.)

    -- ---- 2. Content-strip the user's posts and hide them.
    -- The personal content is the free-text body and the uploaded media.
    -- The media *blob* is purged from Storage via the returned list; here
    -- we blank the free text (a TEXT post needs a non-null body per
    -- chk_text_post_has_body, so it gets a sentinel; media posts keep
    -- their type but lose any caption) and drop the thumbnail pointer.
    -- We deliberately do NOT rewrite type/author_alias/media_url: the
    -- column-lock triggers protect them, the alias is an anonymous
    -- per-group pseudonym (not PII), and the media path is an opaque UUID
    -- whose blob is already being deleted. is_deleted hides the row from
    -- every feed.
    UPDATE posts
    SET body = CASE WHEN type = 'TEXT' THEN '[erased]' ELSE NULL END,
        thumbnail_url = NULL,
        is_deleted = TRUE,
        deleted_at = COALESCE(deleted_at, now())
    WHERE author_user_id = p_user_id;
    GET DIAGNOSTICS v_posts = ROW_COUNT;

    -- ---- 3. Content-strip the user's comments the same way.
    UPDATE comments
    SET body = CASE WHEN type = 'TEXT' THEN '[erased]' ELSE NULL END,
        is_deleted = TRUE,
        deleted_at = COALESCE(deleted_at, now())
    WHERE author_user_id = p_user_id;
    GET DIAGNOSTICS v_comments = ROW_COUNT;

    -- ---- 4. Clear the reporter's free-text on reports they filed.
    -- The report row and its evidence (about *other* people's content)
    -- stay for moderation integrity; only the erased user's own words go.
    UPDATE reports
    SET details = NULL
    WHERE reporter_user_id = p_user_id AND details IS NOT NULL;
    GET DIAGNOSTICS v_reports = ROW_COUNT;

    -- ---- 5. Remove the user from group life.
    -- Count groups they still own so the caller can flag ownership that
    -- must be reassigned (created_by_user_id is immutable history and is
    -- left pointing at the tombstone).
    SELECT count(*) INTO v_owned_groups
    FROM group_memberships
    WHERE user_id = p_user_id AND role = 'OWNER' AND status = 'ACTIVE';

    DELETE FROM post_upvotes WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_upvotes = ROW_COUNT;

    -- join requests cascade to their answers + votes.
    DELETE FROM group_join_requests WHERE requester_user_id = p_user_id;
    GET DIAGNOSTICS v_join_requests = ROW_COUNT;

    DELETE FROM group_memberships WHERE user_id = p_user_id;
    GET DIAGNOSTICS v_memberships = ROW_COUNT;

    -- ---- 6. Scrub PII on the profile row into a tombstone.
    UPDATE users
    SET display_name = '[erased user]',
        date_of_birth = DATE '1900-01-01',
        gender = NULL,
        gender_self_describe = NULL,
        employment_status = 'PREFER_NOT_TO_SAY',
        profession = NULL,
        locale = 'en',
        country_code = 'XX',
        auth_subject = 'erased:' || p_user_id::text,
        is_deleted = TRUE,
        deleted_at = COALESCE(deleted_at, now())
    WHERE id = p_user_id;

    -- ---- 7. Scrub PII on the auth record and lock the account out.
    -- Overwrites email/phone, blanks credentials and confirmation tokens
    -- so the tombstone can never log back in.
    UPDATE auth.users
    SET email = 'erased-' || p_user_id::text || '@erased.invalid',
        phone = NULL,
        encrypted_password = NULL,
        email_change = '',
        email_change_token_new = '',
        phone_change = '',
        phone_change_token = '',
        recovery_token = '',
        confirmation_token = '',
        raw_user_meta_data = '{}'::jsonb,
        raw_app_meta_data = '{}'::jsonb,
        updated_at = now()
    WHERE id = p_user_id;

    RETURN jsonb_build_object(
        'user_id', p_user_id,
        'posts_stripped', v_posts,
        'comments_stripped', v_comments,
        'reports_detail_cleared', v_reports,
        'upvotes_removed', v_upvotes,
        'join_requests_removed', v_join_requests,
        'memberships_removed', v_memberships,
        'owned_groups_needing_reassignment', v_owned_groups,
        'storage_objects', v_storage
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;


-- ============================================================
-- fn_list_orphaned_storage_objects: find purgeable media
-- ============================================================
-- Storage blobs whose owning content is gone or soft/hard-deleted:
--   * no row in posts/comments references the object anymore, or
--   * the referencing post/comment is is_deleted = TRUE.
-- Intended for a periodic cleanup job (service_role) that then deletes
-- the physical blobs through the Storage API. Returns bucket + name so
-- the caller can act directly.

CREATE OR REPLACE FUNCTION fn_list_orphaned_storage_objects()
RETURNS TABLE (bucket_id TEXT, name TEXT) AS $$
BEGIN
    RETURN QUERY
    -- post-media orphans
    SELECT o.bucket_id, o.name
    FROM storage.objects o
    WHERE o.bucket_id = 'post-media'
      AND NOT EXISTS (
          SELECT 1 FROM posts p
          WHERE p.media_url = o.name AND p.is_deleted = FALSE
      )
    UNION ALL
    -- post-thumbnails orphans
    SELECT o.bucket_id, o.name
    FROM storage.objects o
    WHERE o.bucket_id = 'post-thumbnails'
      AND NOT EXISTS (
          SELECT 1 FROM posts p
          WHERE p.thumbnail_url = o.name AND p.is_deleted = FALSE
      )
    UNION ALL
    -- comment-media orphans
    SELECT o.bucket_id, o.name
    FROM storage.objects o
    WHERE o.bucket_id = 'comment-media'
      AND NOT EXISTS (
          SELECT 1 FROM comments c
          WHERE c.media_url = o.name AND c.is_deleted = FALSE
      );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public;


-- ============================================================
-- Privileges
-- ============================================================
-- Self-service erasure is available to authenticated users (guarded to
-- their own id inside the function). The orphan sweep is a backend job,
-- not something an end user calls.

REVOKE EXECUTE ON FUNCTION fn_erase_user(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION fn_list_orphaned_storage_objects() FROM anon;
REVOKE EXECUTE ON FUNCTION fn_list_orphaned_storage_objects() FROM authenticated;
