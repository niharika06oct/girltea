# GirlTea

An anonymous community app where people can vent, support each other, and spill tea
about life — in trusted, closed groups with real approval flows.

## What This App Does

- Users create a profile (name, DOB, gender, employment) and join **closed groups**
  (school friends, college friends, work friends, etc.)
- Groups can be **women-only**, **mixed** (all genders welcome), or **gender-neutral**
  (gender not even asked)
- Private groups are **invite-only** (shared via WhatsApp/link); public groups are
  **discoverable** with a request-to-join flow
- Joining any group requires **2 members to approve** after reviewing your answers to
  entry questions — no single person has unilateral power
- Members can post **text, images, videos, or voice recordings** (video/voice capped
  at 3 minutes) and comment on posts (text, image, or voice)
- Removing a member also requires **2 people to agree** (one raises the request, one
  more approves)
- Everything is backed by PostgreSQL with Supabase for auth, storage, and RLS

## Project Structure

```
girltea/
├── README.md                          ← You are here
├── schema/                            ← PostgreSQL data model (21 SQL files)
│   ├── 001_enums.sql                  ← All enum types
│   ├── 002_users.sql                  ← User profiles
│   ├── 003_groups.sql                 ← Groups with policy/visibility/settings
│   ├── 004_group_memberships.sql      ← Who belongs to which group
│   ├── 005_group_invites.sql          ← Invite link tokens
│   ├── 006_group_entry_questions.sql  ← Per-group questionnaires
│   ├── 007_group_join_requests.sql    ← Join requests
│   ├── 008_group_join_request_answers.sql ← Answers to entry questions
│   ├── 009_group_join_votes.sql       ← Approval/rejection votes
│   ├── 010_posts.sql                  ← Posts (text/image/video/voice)
│   ├── 011_comments.sql               ← Comments (text/image/voice)
│   ├── 012_reports.sql                ← Moderation reports
│   ├── 013_indexes.sql                ← All indexes
│   ├── 014_triggers.sql               ← Triggers (member count, timestamps, expiry)
│   ├── 015_approval_logic.sql         ← Transactional join approval function
│   ├── 016_group_removal_requests.sql ← Democratic removal requests
│   ├── 017_group_removal_votes.sql    ← Removal votes
│   ├── 018_removal_logic.sql          ← Transactional removal function
│   ├── 019_post_upvotes.sql           ← Upvote tracking
│   ├── 020_alias_generator.sql        ← fn_generate_alias() for per-group aliases
│   ├── 021_hub_rpcs.sql               ← Hub RPCs (create group, resolve invite, join, pending votes)
│   ├── 022_moderation.sql             ← Moderation queue + actions
│   ├── 023_erasure.sql                ← Right-to-erasure purge path (DPDP/GDPR)
│   ├── 024_group_slugs.sql            ← Readable group slugs for URLs (/college-girls)
│   ├── DESIGN.md                      ← Design decisions, flow diagrams, matrices
│   ├── schema-diagram.png             ← ER diagram (high-res)
│   ├── schema-diagram.svg             ← ER diagram (scalable)
│   └── schema-diagram.mmd            ← ER diagram (editable Mermaid source)
├── supabase/                          ← Supabase configuration
│   ├── config.toml                    ← Supabase CLI config for local dev stack
│   ├── auth_setup.sql                 ← Links app users to Supabase Auth
│   ├── auth_helpers.sql               ← Auth helper functions used by RLS/RPCs
│   ├── rls_policies.sql               ← Row Level Security for all 14 tables
│   ├── storage_buckets.sql            ← Storage bucket definitions
│   ├── storage_policies.sql           ← Storage access policies
│   ├── AUTH.md                        ← Auth setup guide + Flutter examples
│   ├── STORAGE.md                     ← Storage architecture + setup guide
│   └── QUERIES.md                     ← Complete query reference for Flutter app
├── app/                               ← Flutter web client (see app/README.md)
└── scripts/
    └── dev-code.sh                    ← Prints an instant sign-in OTP for local dev
```

## Schema Diagram

![Schema Diagram](schema/schema-diagram.png)

14 tables, every column with its type, and all foreign key relationships. Also
available as [SVG](schema/schema-diagram.svg) and editable
[Mermaid source](schema/schema-diagram.mmd).

## Data Model (14 tables)

### Users & Identity

| Table | Purpose |
|---|---|
| `users` | Profile: display name, date of birth, gender (9 options + self-describe + prefer not to say), employment status, profession. Soft-delete for GDPR/DPDP. Minimum age 13 enforced. `users.id` = Supabase `auth.users.id`. |

### Groups & Membership

| Table | Purpose |
|---|---|
| `groups` | Name, description, policy (`WOMEN_ONLY` / `MIXED` / `GENDER_NEUTRAL`), visibility (`LINK_ONLY` / `DISCOVERABLE`), category tags, configurable approval settings (JSON). Member count maintained via trigger. |
| `group_memberships` | Links users to groups. Role: `OWNER` / `ADMIN` / `MEMBER`. Status: `ACTIVE` / `BANNED` / `LEFT`. Composite PK `(group_id, user_id)`. |
| `group_invites` | Token-based invite links for sharing via WhatsApp etc. Supports expiry, max uses, revocation. |

### Join Flow (request → entry questions → vote → admit)

| Table | Purpose |
|---|---|
| `group_entry_questions` | Per-group questionnaire (short text, long text, single/multi choice). Versioned so edits don't orphan old answers. |
| `group_join_requests` | One pending request per user per group (partial unique index). Tracks source (`INVITE_LINK` / `SUGGESTION` / `MANUAL_SEARCH`). Auto-expires after 14 days. |
| `group_join_request_answers` | Answers to entry questions, linked to question version. Shown to voters. |
| `group_join_votes` | Approval/rejection with voter's role snapshot. One vote per person per request. |

### Democratic Removal Flow (raise → vote → ban)

| Table | Purpose |
|---|---|
| `group_removal_requests` | Any member raises a request against another member with a reason. One pending removal per target per group. Expires after 7 days. |
| `group_removal_votes` | Requester's APPROVE vote auto-recorded; one more member must agree for quorum of 2. |

### Content

| Table | Purpose |
|---|---|
| `posts` | Types: `TEXT`, `IMAGE`, `VIDEO`, `VOICE`. Each media post is standalone. Video/voice max 180 seconds (DB constraint). Soft-delete. |
| `comments` | Types: `TEXT`, `IMAGE`, `VOICE`. Single-level (no reply threads). Same 3-min voice cap. |
| `post_upvotes` | Composite PK `(post_id, user_id)` prevents double-taps. Trigger maintains `posts.upvote_count`. |
| `reports` | Moderation reports against any entity (post, comment, user, group). |

## Key Design Decisions

### Group Policies (who can join)

| Policy | Gender required at join? | Rule |
|---|---|---|
| `WOMEN_ONLY` | Yes, must be `WOMAN` | Gate at request time |
| `MIXED` | Yes, any value (including `PREFER_NOT_TO_SAY`) | User acknowledges multi-gender space |
| `GENDER_NEUTRAL` | No | Gender not part of the membership contract |

### Group Visibility (how users find groups)

| Visibility | In suggestions? | How user finds it |
|---|---|---|
| `LINK_ONLY` | No | Invite link only (WhatsApp, SMS, etc.) |
| `DISCOVERABLE` | Yes | Browse/search, filtered by tags and country |

### Democratic Authority (no single-person power)

For groups under `democraticThreshold` (default 10 members):
- **Admission**: Always requires 2+ members to approve — no owner/admin override
- **Removal**: Requester + 1 other member must agree — no one can solo-remove

For larger groups, configurable via `groups.settings` JSON:

```json
{
  "approvalMode": "HYBRID",
  "memberApproverQuorum": 2,
  "memberApprovalMaxGroupSize": 20,
  "largeGroupApprovalMode": "ADMINS_ONLY",
  "joinRequestTtlHours": 336,
  "allowInviteLink": true,
  "removalQuorum": 2,
  "removalRequestTtlHours": 168,
  "democraticThreshold": 10
}
```

### Content Rules

| Post/comment type | Required fields | Max duration | Max file size |
|---|---|---|---|
| `TEXT` | `body` | — | — |
| `IMAGE` | `media_url` | — | 10 MB |
| `VIDEO` (posts only) | `media_url`, `duration_seconds` | 180s (3 min) | 100 MB |
| `VOICE` | `media_url`, `duration_seconds` | 180s (3 min) | 10 MB |

## Authentication

Phone/email OTP via **Supabase Auth** — no passwords, no social login.

```
Enter phone/email → receive 6-digit OTP → verify
  → No profile? → Onboarding screen (name, DOB, gender, employment)
  → Has profile? → Circles overview (/home)
```

The web client uses real, shareable URLs (via `go_router`): `/home` (your
circles), `/:group-slug` (a circle's feed), and `/:group-slug/:postId` (a single
post + its tea). Group slugs are readable and derived from the group name by
`024_group_slugs.sql`.

- `users.id` = `auth.users.id` (same UUID, linked via FK)
- Profile created at onboarding, not automatically on signup (keeps NOT NULL
  constraints intact)
- Session tokens managed by Supabase SDK (auto-refresh)

| File | Purpose |
|---|---|
| `supabase/auth_setup.sql` | FK to `auth.users`, helper functions `fn_has_profile()`, `fn_my_profile()` |
| `supabase/auth_helpers.sql` | Additional auth helper functions used by RLS policies and RPCs |
| `supabase/rls_policies.sql` | Row Level Security policies for all 14 tables |
| `supabase/AUTH.md` | Full setup guide: enable OTP, Flutter code examples, SMS costs |

## Row Level Security (RLS)

Every table has RLS enabled. Users can only access data they're authorized for:

| What | Who can see it | Who can write |
|---|---|---|
| Your profile | You only | You only |
| Discoverable groups | All authenticated users | Creator |
| Private (LINK_ONLY) groups | Members only | Creator |
| Posts, comments, upvotes | Group members only | Group members (own content) |
| Join requests + answers | Requester + group members | Requester |
| Join/removal votes | Group members | Group members |
| Reports | Your own reports | Any authenticated user |

## Supabase Storage

Media files stored in **Supabase Storage** (free: 1 GB storage, 2 GB bandwidth/month,
no credit card). Database stores only URL references (`media_url`, `thumbnail_url`).

| Bucket | Contents | Max file size |
|---|---|---|
| `post-media` | Images, videos, voice for posts | 100 MB |
| `post-thumbnails` | Video thumbnail previews | 2 MB |
| `comment-media` | Images, voice for comments | 10 MB |

| File | Purpose |
|---|---|
| `supabase/storage_buckets.sql` | Bucket definitions (run once in SQL Editor) |
| `supabase/storage_policies.sql` | RLS policies for storage access |
| `supabase/STORAGE.md` | Full architecture: upload flow, setup instructions, cost notes |

## Triggers & Functions

| Function | What it does |
|---|---|
| `fn_update_group_member_count()` | Trigger: atomically maintains `groups.member_count` |
| `fn_update_post_upvote_count()` | Trigger: atomically maintains `posts.upvote_count` |
| `fn_set_updated_at()` | Trigger: auto-sets `updated_at` on row changes |
| `fn_expire_stale_requests()` | Scheduled: expires old join + removal requests |
| `fn_cast_join_vote()` | Transaction: vote → check quorum → maybe admit (atomic) |
| `fn_validate_join_eligibility()` | Checks gender policy before allowing a join request |
| `fn_cast_removal_vote()` | Transaction: vote → check quorum → maybe ban (atomic) |
| `fn_raise_removal_request()` | Creates request + auto-records requester's APPROVE vote |
| `fn_has_profile()` | Returns whether the current auth user has completed onboarding |
| `fn_my_profile()` | Returns the current auth user's profile row |

## Getting Started (for new team members)

### 1. Clone the repo

```bash
git clone https://github.com/niharika06oct/girltea.git
cd girltea
```

### 2. Create a Supabase project

1. Go to [supabase.com](https://supabase.com) → sign up (free, no credit card)
2. Create new project: name `girltea`, region closest to India
3. Save the database password

### 3. Run the schema

Apply the SQL in **dependency order, not strict numeric order** — `013_indexes.sql`
and `014_triggers.sql` reference tables created in later-numbered files (`016`, `017`,
`019`), so running them in plain 001→021 order fails. Run all table/enum DDL first,
then indexes/triggers/functions:

1. Tables & enums: `001_enums` → `012_reports`, then `016_group_removal_requests`,
   `017_group_removal_votes`, `019_post_upvotes`
2. Indexes & triggers: `013_indexes`, `014_triggers`
3. Functions & RPCs: `020_alias_generator`, `015_approval_logic`, `018_removal_logic`,
   `021_hub_rpcs`, `022_moderation`, `023_erasure`, `024_group_slugs`

If you have the Supabase CLI and `psql` locally, the loop in `AGENTS.md` applies
everything in the correct order in one step.

### 4. Set up auth

1. Run `supabase/auth_setup.sql`, then `supabase/auth_helpers.sql` in the SQL Editor
2. Enable Phone and/or Email OTP in **Authentication** → **Providers**
3. See `supabase/AUTH.md` for detailed steps

### 5. Set up storage

1. Run `supabase/storage_buckets.sql` in the SQL Editor
2. Run `supabase/storage_policies.sql` in the SQL Editor
3. See `supabase/STORAGE.md` for detailed steps

### 6. Apply RLS policies

1. Run `supabase/rls_policies.sql` in the SQL Editor

### 7. Get your credentials

In **Settings** → **API**, copy:
- **Project URL**: `https://xxxxx.supabase.co`
- **Anon public key**: `eyJhb...`

These go into the Flutter app's Supabase initialization.

## What's Not Built Yet

| Area | Status |
|---|---|
| Flutter app — auth, group feed, posts (text/image/video/voice), threaded comments, upvotes | Built |
| Flutter app — group creation, join/approval, removal flows | Not started — next step |
| Push notifications | Not started |
| Cloud Function for video duration validation (FFprobe) | Deferred to post-MVP |
| Image thumbnail generation | Deferred to post-MVP |
| EXIF stripping for image privacy | Deferred to post-MVP |

## Documentation Index

| Document | What's in it |
|---|---|
| This README | Project overview, schema summary, setup instructions |
| `schema/DESIGN.md` | Full design rationale, suggestion assessment, approval/removal/visibility matrices, content model |
| `supabase/AUTH.md` | Auth setup guide, OTP config, Flutter code examples, SMS costs |
| `supabase/STORAGE.md` | Storage architecture, upload flow, bucket structure, MIME types, cost optimization |
