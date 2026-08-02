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

CREATE OR REPLACE FUNCTION fn_generate_alias()
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
BEGIN
    RETURN adjectives[1 + floor(random() * array_length(adjectives, 1))::INT]
        || nouns[1 + floor(random() * array_length(nouns, 1))::INT]
        || lpad(floor(random() * 100)::TEXT, 2, '0');
END;
$$ LANGUAGE plpgsql;
