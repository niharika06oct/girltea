# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is
This is a **database-only project** (the "GirlTea" app data model). There is no
application/server/Flutter code yet — the deliverable is a PostgreSQL data model
plus Supabase auth/storage/RLS. See `README.md` and `schema/DESIGN.md` for design
details. The "app" you run is therefore the **local Supabase stack** (Postgres +
Auth + Storage + Studio), and you validate changes by applying the SQL and
exercising the RPCs/triggers/RLS.

### Toolchain / dependencies
- Requires **Docker** and the **Supabase CLI** (installed by the startup update
  script; Docker + pulled images are expected to come from the environment
  snapshot). `psql` and Node.js are also handy and available.
- There are **no language package manifests** (no `package.json`,
  `requirements.txt`, etc.) and **no automated test suite / build step**.

### Bringing the stack up (services are NOT auto-started)
1. Docker is not a systemd service here — start the daemon yourself if it isn't
   running, e.g. `sudo dockerd > /tmp/dockerd.log 2>&1 &`, then make the socket
   usable without sudo: `sudo chmod 666 /var/run/docker.sock`.
2. From the repo root: `supabase start` (first run pulls images; ~1 min after
   that). Key endpoints it prints: DB `postgresql://postgres:postgres@127.0.0.1:54322/postgres`,
   Studio `http://127.0.0.1:54323`, API `http://127.0.0.1:54321`.
3. `supabase init` created `supabase/config.toml`. If that file was not merged,
   run `supabase init` (answer `n` to the Deno prompts) before `supabase start`.

### Applying the SQL — order matters (non-obvious)
Do **not** apply `schema/*.sql` in strict numeric order: `schema/013_indexes.sql`
and `schema/014_triggers.sql` reference tables that are created in *later*-numbered
files (`019_post_upvotes`, `016`/`017` removal tables). The README's "Getting
Started" ordering is imperfect for this reason. Apply in dependency order — all
table/enum DDL first, then indexes/triggers/functions, then the Supabase files:

```bash
DBURL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
for n in 001_enums 002_users 003_groups 004_group_memberships 005_group_invites \
  006_group_entry_questions 007_group_join_requests 008_group_join_request_answers \
  009_group_join_votes 010_posts 011_comments 012_reports 016_group_removal_requests \
  017_group_removal_votes 019_post_upvotes \
  013_indexes 014_triggers 020_alias_generator 015_approval_logic 018_removal_logic 021_hub_rpcs \
  022_moderation 023_erasure; do
  psql "$DBURL" -v ON_ERROR_STOP=1 -f "schema/$n.sql"; done
for f in supabase/auth_setup.sql supabase/auth_helpers.sql supabase/storage_buckets.sql \
  supabase/storage_policies.sql supabase/grants.sql supabase/rls_policies.sql; do
  psql "$DBURL" -v ON_ERROR_STOP=1 -f "$f"; done
```

`supabase db reset` gives you a clean database (drops everything, re-seeds roles)
before re-applying. The `supabase/*.sql` files depend on the Supabase-only `auth`
and `storage` schemas, so plain Postgres is not sufficient — use the local stack.

### Lint
`supabase db lint` runs plpgsql checks against the running DB. It currently
reports only benign warnings (unread variables, one control-flow warning); there
are no errors. There is no other linter configured.

### Testing the data model (how to act as a logged-in user)
Almost all logic lives in `SECURITY DEFINER` RPCs that read `auth.uid()`, and RLS
policies also key off `auth.uid()`. To simulate a signed-in user from `psql`:
`SELECT set_config('request.jwt.claims', '{"sub":"<user-uuid>","role":"authenticated"}', false);`
then call the RPC. To exercise RLS as a non-owner, additionally `SET ROLE authenticated;`
(the `postgres` superuser bypasses RLS). Create real auth users (so the
`users.id -> auth.users.id` FK is satisfied) via the GoTrue admin API using the
service-role key printed by `supabase start`:
`POST http://127.0.0.1:54321/auth/v1/admin/users` with `{"email":...,"password":...,"email_confirm":true}`.

Bootstrapping note: a brand-new group has only its OWNER, but the first joins need
a 2-approver quorum, so seed a second founding member directly into
`group_memberships` before demonstrating the RPC-based join/vote flow.
