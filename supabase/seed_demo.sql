-- ============================================================
-- GirlTea — Demo seed (local dev only)
-- ============================================================
-- Walks the real RPC flow so triggers / quorum logic are visible
-- in Studio. Idempotent-ish: run after `supabase db reset` +
-- re-applying schema. Uses fixed UUIDs.
--
-- Cast of characters (all women, so a WOMEN_ONLY group works):
--   Aisha   — creates the group (OWNER)
--   Bela    — founding member (seeded, so a 2-vote quorum exists)
--   Chandni — founding member (seeded)
--   Diya    — outsider who requests to join and gets admitted
-- ============================================================

BEGIN;

-- --- fixed UUIDs -------------------------------------------------
\set aisha   '11111111-1111-1111-1111-111111111111'
\set bela    '22222222-2222-2222-2222-222222222222'
\set chandni '33333333-3333-3333-3333-333333333333'
\set diya    '44444444-4444-4444-4444-444444444444'

-- --- auth.users (FK target for users.id) ------------------------
INSERT INTO auth.users (id, email)
VALUES (:'aisha','aisha@example.com'),
       (:'bela','bela@example.com'),
       (:'chandni','chandni@example.com'),
       (:'diya','diya@example.com')
ON CONFLICT (id) DO NOTHING;

-- --- app profiles ------------------------------------------------
INSERT INTO users (id, auth_subject, display_name, date_of_birth, gender, employment_status, profession)
VALUES
  (:'aisha',   :'aisha',   'Aisha',   '1996-04-12', 'WOMAN', 'WORKING', 'Designer'),
  (:'bela',    :'bela',    'Bela',    '1998-09-01', 'WOMAN', 'NOT_WORKING', NULL),
  (:'chandni', :'chandni', 'Chandni', '1994-01-22', 'WOMAN', 'WORKING', 'Doctor'),
  (:'diya',    :'diya',    'Diya',    '2000-07-30', 'WOMAN', 'NOT_WORKING', NULL)
ON CONFLICT (id) DO NOTHING;

-- --- Aisha creates a WOMEN_ONLY group via the real RPC ----------
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'aisha', 'role', 'authenticated')::text, true);

SELECT fn_create_group_with_owner(
  'College Girls',
  'Safe space to vent about campus life.',
  'WOMEN_ONLY'::group_policy,
  'LINK_ONLY'::group_visibility,
  ARRAY['college','support']
) AS new_group_id \gset

-- --- one required entry question --------------------------------
INSERT INTO group_entry_questions (group_id, sort_order, prompt, question_type, is_required)
VALUES (:'new_group_id', 1, 'Which college / batch are you from?', 'SHORT_TEXT', TRUE)
RETURNING id AS q_id \gset

-- --- seed Bela & Chandni as founding members --------------------
-- (bootstrapping: a fresh group has only its OWNER, but joins need
--  a 2-approver quorum, so we need two more active members.)
INSERT INTO group_memberships (group_id, user_id, role, status, alias)
VALUES
  (:'new_group_id', :'bela',    'MEMBER', 'ACTIVE', fn_generate_alias_for_group(:'new_group_id')),
  (:'new_group_id', :'chandni', 'MEMBER', 'ACTIVE', fn_generate_alias_for_group(:'new_group_id'))
ON CONFLICT (group_id, user_id) DO NOTHING;

-- --- Diya submits a join request (answering the question) -------
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'diya', 'role', 'authenticated')::text, true);

SELECT fn_submit_join_request(
  :'new_group_id',
  NULL,
  'MANUAL_SEARCH'::join_request_source,
  json_build_array(
    json_build_object('question_id', :'q_id', 'question_version', 1,
                      'answer_text', 'Class of 2022, St. Xavier''s')
  )::jsonb
) AS req_id \gset

-- --- Bela votes APPROVE (1/2) -----------------------------------
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'bela', 'role', 'authenticated')::text, true);
SELECT * FROM fn_cast_join_vote(:'req_id', 'APPROVE'::vote_decision);

-- --- Chandni votes APPROVE (2/2 → quorum → Diya admitted) -------
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'chandni', 'role', 'authenticated')::text, true);
SELECT * FROM fn_cast_join_vote(:'req_id', 'APPROVE'::vote_decision);

-- --- Diya (now a member) writes a post, Aisha upvotes it --------
SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'diya', 'role', 'authenticated')::text, true);

SELECT alias AS diya_alias
FROM group_memberships
WHERE group_id = :'new_group_id' AND user_id = :'diya' \gset

INSERT INTO posts (group_id, author_user_id, author_alias, type, body)
VALUES (:'new_group_id', :'diya', :'diya_alias', 'TEXT', 'Finally in! Hi everyone 👋')
RETURNING id AS post_id \gset

SELECT set_config('request.jwt.claims',
  json_build_object('sub', :'aisha', 'role', 'authenticated')::text, true);
INSERT INTO post_upvotes (post_id, user_id)
VALUES (:'post_id', :'aisha')
ON CONFLICT DO NOTHING;

COMMIT;
