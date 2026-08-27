-- ============================================================
-- GirlTea App — Migration 025: Circle Identity
-- ============================================================
-- Additive. Each circle can carry its own emoji, accent colour and
-- cover image so switching circles feels like walking into a different
-- room. No data is dropped; existing reads keep working (new columns are
-- nullable). fn_create_group_with_owner gains optional params with
-- defaults so the old 5-arg call site keeps working unchanged.
--
-- Apply order: after the base schema. Safe to re-run (idempotent).

-- ---- New columns on groups ----
ALTER TABLE groups ADD COLUMN IF NOT EXISTS emoji            TEXT;
ALTER TABLE groups ADD COLUMN IF NOT EXISTS accent_color     TEXT;
ALTER TABLE groups ADD COLUMN IF NOT EXISTS cover_image_url  TEXT;

-- Light validation: accent_color, when set, must look like a hex colour.
-- (Kept permissive: #RGB / #RRGGBB / #AARRGGBB, case-insensitive.)
ALTER TABLE groups DROP CONSTRAINT IF EXISTS chk_accent_color_hex;
ALTER TABLE groups ADD CONSTRAINT chk_accent_color_hex
    CHECK (accent_color IS NULL OR accent_color ~* '^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$');

-- ============================================================
-- fn_create_group_with_owner — extend with identity params
-- ============================================================
-- CREATE OR REPLACE cannot add parameters (it would create an overload
-- and make PostgREST ambiguous for the old arg set), so DROP the exact
-- old signature and recreate with the new optional params appended.
DROP FUNCTION IF EXISTS fn_create_group_with_owner(
    TEXT, TEXT, group_policy, group_visibility, TEXT[]
);

CREATE OR REPLACE FUNCTION fn_create_group_with_owner(
    p_name TEXT,
    p_description TEXT DEFAULT NULL,
    p_policy group_policy DEFAULT 'GENDER_NEUTRAL',
    p_visibility group_visibility DEFAULT 'LINK_ONLY',
    p_category_tags TEXT[] DEFAULT '{}',
    p_emoji TEXT DEFAULT NULL,
    p_accent_color TEXT DEFAULT NULL,
    p_cover_image_url TEXT DEFAULT NULL
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

    INSERT INTO groups (
        name, description, policy, visibility, category_tags,
        emoji, accent_color, cover_image_url, created_by_user_id
    )
    VALUES (
        p_name, p_description, p_policy, p_visibility, p_category_tags,
        p_emoji, p_accent_color, p_cover_image_url, v_caller
    )
    RETURNING id INTO v_group_id;

    -- Snapshot the owner's gender AS OF creation (see 004_group_memberships).
    INSERT INTO group_memberships (group_id, user_id, role, status, alias, gender_at_admission)
    VALUES (v_group_id, v_caller, 'OWNER', 'ACTIVE', fn_generate_alias_for_group(v_group_id), v_user_gender);

    RETURN v_group_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
