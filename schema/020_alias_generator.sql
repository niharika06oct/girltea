-- ============================================================
-- GirlTea App — Alias Generator
-- ============================================================
-- Generates anonymous aliases for group memberships.
-- Alias is stable per group: you're the same alias across all
-- your posts/comments in that group, but a different alias in
-- each group you belong to.
--
-- Posts and comments snapshot the alias at write time from
-- group_memberships.alias — so if a member's alias is later
-- regenerated, their old posts keep the old alias (thread
-- continuity is preserved).
--
-- UNIQUE(group_id, alias) on group_memberships prevents
-- collisions. This function retries on conflict.

CREATE OR REPLACE FUNCTION fn_generate_alias_for_group(p_group_id UUID)
RETURNS TEXT AS $$
DECLARE
    adjectives TEXT[] := ARRAY[
        'Wild', 'Stormy', 'Cosmic', 'Velvet', 'Neon',
        'Mystic', 'Golden', 'Shadow', 'Fierce', 'Gentle',
        'Bold', 'Silent', 'Radiant', 'Midnight', 'Crystal',
        'Electric', 'Dreamy', 'Rebel', 'Lunar', 'Crimson'
    ];
    nouns TEXT[] := ARRAY[
        'Orchid', 'Phoenix', 'Muse', 'Tiger', 'Raven',
        'Tulip', 'Spark', 'Wave', 'Echo', 'Sage',
        'Flame', 'Fern', 'Star', 'Storm', 'Pearl',
        'Fox', 'Dove', 'Lotus', 'Comet', 'Ember'
    ];
    v_alias TEXT;
    v_attempts INT := 0;
BEGIN
    LOOP
        v_alias := adjectives[1 + floor(random() * array_length(adjectives, 1))::INT]
            || nouns[1 + floor(random() * array_length(nouns, 1))::INT]
            || lpad(floor(random() * 100)::TEXT, 2, '0');

        IF NOT EXISTS (
            SELECT 1 FROM group_memberships
            WHERE group_id = p_group_id AND alias = v_alias
        ) THEN
            RETURN v_alias;
        END IF;

        v_attempts := v_attempts + 1;
        IF v_attempts > 50 THEN
            RAISE EXCEPTION 'Could not generate unique alias after 50 attempts (group: %)', p_group_id;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;
