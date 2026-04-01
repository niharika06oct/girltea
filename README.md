# GirlTea

An anonymous community app where people can vent, support each other, and spill tea
about life — in trusted, closed groups with real approval flows.

## Data Model

The PostgreSQL schema lives in `schema/` and is split into numbered migration files:

| File | Contents |
|---|---|
| `001_enums.sql` | All enum types (gender, group policy, visibility, roles, etc.) |
| `002_users.sql` | User profiles (name, DOB, gender, employment, soft-delete) |
| `003_groups.sql` | Groups with policy, visibility, JSON settings, member count |
| `004_group_memberships.sql` | Membership join table (role, status) |
| `005_group_invites.sql` | Invite link tokens for LINK_ONLY groups |
| `006_group_entry_questions.sql` | Per-group questionnaire with versioning |
| `007_group_join_requests.sql` | Join requests with status, source, expiry |
| `008_group_join_request_answers.sql` | Answers to entry questions per request |
| `009_group_join_votes.sql` | Approval / rejection votes with role snapshot |
| `010_posts.sql` | Posts (text, image, audio) with soft-delete |
| `011_comments.sql` | Single-level comments on posts |
| `012_reports.sql` | Moderation reports |
| `013_indexes.sql` | All indexes (partial, GIN, composite) |
| `014_triggers.sql` | Triggers for member count, updated_at, request expiry |
| `015_approval_logic.sql` | Transactional vote + admit function, eligibility check |

See `schema/DESIGN.md` for the full rationale behind each design decision, the
suggestion assessment, and the approval/visibility/policy matrices.

## Key Concepts

- **Group policies**: `WOMEN_ONLY`, `MIXED`, `GENDER_NEUTRAL` — controls who can request to join
- **Group visibility**: `LINK_ONLY` (invite link required), `DISCOVERABLE` (appears in suggestions)
- **Approval flow**: Configurable quorum (default 2 approvers); switches to admin-only above a configurable group size
- **Entry questions**: Groups can define questionnaires; answers are shown to voters
- **Soft deletes**: Users, groups, posts, and comments support reversible deletion
