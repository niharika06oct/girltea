# GirlTea — Data Model Design Notes

## Schema Diagram

![Schema Diagram](schema-diagram.png)

The full ER diagram is also available as [SVG](schema-diagram.svg) and editable [Mermaid source](schema-diagram.mmd).

---

## Content Model (Posts & Comments)

### Posts

Each post is one of three types — no mixing media within a single post:

| Type | Required fields | Constraints |
|---|---|---|
| `TEXT` | `body` | — |
| `VIDEO` | `media_url`, `duration_seconds` | Max 180 seconds (3 minutes) |
| `VOICE` | `media_url`, `duration_seconds` | Max 180 seconds (3 minutes) |

- `thumbnail_url` is optional on video posts (for feed previews)
- `body` can optionally accompany a video/voice post as a caption
- DB CHECK constraints enforce: text posts must have body, media posts must have URL and duration, duration cannot exceed 180s

### Comments

Comments on any post type support text and voice:

| Type | Required fields | Constraints |
|---|---|---|
| `TEXT` | `body` | — |
| `VOICE` | `media_url`, `duration_seconds` | Max 180 seconds (3 minutes) |

- No video comments — keeps the comment thread lightweight
- Single-level nesting (no replies to replies)

---

## Suggestion Assessment

Below is a point-by-point review of each suggestion from the schema review, with the
decision (adopted, deferred, or skipped) and rationale.

---

### 1. Profile (`users`)

| Suggestion | Decision | Rationale |
|---|---|---|
| **Soft-delete** (`isDeleted` + `deletedAt`) for reversible account deletion + 30-day PII purge job | **Adopted** | Essential for GDPR / DPDP "right to be forgotten" and undo-delete UX. Added `is_deleted`, `deleted_at`, and a CHECK constraint linking them. |
| **`dateOfBirth`** instead of integer `age` | **Adopted** | Age as int drifts silently; `date_of_birth` is canonical. App derives age via `CURRENT_DATE - date_of_birth`. Also enables the 13+ minimum-age CHECK. |
| **Profession lookup table** for analytics | **Deferred** | Free text `profession` is fine for MVP. A lookup table can be added later once we see the actual distribution of values and the analytics needs are clear. |

### 2. Groups

| Suggestion | Decision | Rationale |
|---|---|---|
| **Promote `visibility` to enum** with `LINK_ONLY`, `DISCOVERABLE` (and future `PUBLIC_SUGGESTED`) | **Adopted** | Enum prevents stringly-typed bugs and makes adding future values a one-line `ALTER TYPE`. |
| **`memberCount` via trigger** for race-condition safety | **Adopted** | Trigger on `group_memberships` increments/decrements atomically inside the same transaction. |
| **Partial indexes on JSON `settings`** | **Adopted** | Added index on `settings->>'memberApproverQuorum'` for discoverable groups. More can be added as query patterns emerge. |

### 3. Join Workflow

| Suggestion | Decision | Rationale |
|---|---|---|
| **`source` enum** (`INVITE_LINK`, `SUGGESTION`, `MANUAL_SEARCH`) on join requests | **Adopted** | Low-cost addition that enables funnel analytics from day 1. |
| **Unique partial index** for one pending request per user/group | **Adopted** | `CREATE UNIQUE INDEX ... WHERE status='PENDING'` on `(group_id, requester_user_id)`. Prevents duplicate pending requests at the DB level. |
| **`voterRole`** on votes | **Adopted** | Captures the voter's role at the time of voting. Useful when quorum rules change—no need to re-derive historical eligibility. |
| **Single transaction** for "cast vote → maybe admit" | **Adopted** | `fn_cast_join_vote()` locks the join request row, records the vote, checks quorum, and inserts membership—all in one atomic function call. |

### 4. Entry Questions

| Suggestion | Decision | Rationale |
|---|---|---|
| **Version column** on questions | **Adopted** | `version` on `group_entry_questions` + `question_version` on answers so edits don't orphan historical responses. |
| **Encrypt answers at rest** | **Deferred** | Depends on infrastructure (pgcrypto, app-level encryption, or managed KMS). Noted for hardening phase; not blocking MVP. |

### 5. Indexes

| Suggestion | Decision | Rationale |
|---|---|---|
| **Day-1 indexes** on `(groupId, status)`, `(visibility, policy)`, `(groupId, createdAt DESC)` | **Adopted** | All present in `013_indexes.sql`. Additional indexes for users, invites, reports, and answers also added. |

### 6. Privacy & Compliance

| Suggestion | Decision | Rationale |
|---|---|---|
| **`createdAt` / `updatedAt` / `deletedAt`** on every table | **Adopted** | All mutable tables have audit timestamps. |
| **Cascade deletes / scramble author tags** for right to be forgotten | **Partially adopted** | Foreign keys use `ON DELETE CASCADE` where appropriate. Full PII scrubbing (e.g. nullify `author_alias` on posts) is an app-level job, not schema-level—noted for implementation. |
| **Minimize PII** (gender & DOB server-side only) | **Adopted** | These fields exist only in `users`; the app layer should never expose raw DOB or gender in public-facing APIs. |

### 7. Scaling Notes

| Suggestion | Decision | Rationale |
|---|---|---|
| **Shard `group_join_requests` by month** | **Deferred** | Premature at MVP scale. Partitioning can be added later without schema changes to consumers (Postgres native partitioning on `created_at`). |
| **Partition posts by `groupId` + monthly suffix** | **Deferred** | Same reasoning. The `idx_posts_group_feed` index handles feed queries at current scale. |
| **Push join-request events to a queue** (Pub/Sub, SQS) | **Deferred** | Architecture decision, not schema. The atomic `fn_cast_join_vote` function keeps the DB consistent; event publishing can wrap it at the API layer when needed. |

---

## Democratic Authority Model

No single person has unilateral power in a group. All high-impact actions require
consensus from at least two members, especially in small trusted circles.

### Guiding Principle

> For groups under the democratic threshold (default 10 members), every member is
> equal. OWNER/ADMIN roles exist for coordination in larger groups, not for
> authority in small ones.

### Admission: always requires 2+ approvers

| Group size | Who can vote | Quorum |
|---|---|---|
| Below `democraticThreshold` (< 10) | Any active member | 2 (minimum, cannot be lowered) |
| Above threshold, `MEMBERS_QUORUM` | Any active member | `memberApproverQuorum` from settings |
| Above threshold, `ADMINS_ONLY` | OWNER / ADMIN only | `memberApproverQuorum` from settings |
| Above threshold, `HYBRID` below `memberApprovalMaxGroupSize` | Any active member | `memberApproverQuorum` from settings |
| Above threshold, `HYBRID` above `memberApprovalMaxGroupSize` | Falls back to `largeGroupApprovalMode` | `memberApproverQuorum` from settings |

### Removal: raise + second approval

Any member can raise a request to remove another member. The requester's intent
automatically counts as the first APPROVE vote. One more member must approve for the
removal to go through (for groups under the democratic threshold).

```
Member A raises removal request against Member B
        │
        ▼
group_removal_requests row created (PENDING)
  + auto-vote: Member A → APPROVE (counted as vote #1)
        │
        ▼
Other members see the request + reason
        │
        ▼
Member C votes APPROVE → quorum (2) reached
        │
        ▼
Member B's membership status → BANNED
```

| Group size | Quorum for removal |
|---|---|
| Below `democraticThreshold` (< 10) | 2 (requester + 1 other) |
| Above threshold | `removalQuorum` from settings (configurable) |

### What no single person can do

- Admit someone alone (always 2+ approvers)
- Remove someone alone (always requester + 1 other)
- Override a vote outcome

### Settings changes (future consideration)

For MVP, group settings are set at creation time. Changing settings (policy, visibility,
approval rules) can later be gated behind a vote as well, consistent with the democratic
model. This keeps the schema simple now without blocking the design direction.

---

## Approval Flow Summary

```
User taps "Join" on a group
        │
        ▼
fn_validate_join_eligibility()
  ├── WOMEN_ONLY → gender must be WOMAN
  ├── MIXED → gender must be set (any value including PREFER_NOT_TO_SAY)
  └── GENDER_NEUTRAL → no check
        │
        ▼
Insert group_join_request (status = PENDING)
  + Insert group_join_request_answers (entry question responses)
        │
        ▼
Existing members/admins see request + answers
        │
        ▼
fn_cast_join_vote(request, voter, APPROVE/REJECT)
  ├── Checks voter eligibility (active member, correct role for approval mode)
  ├── Records vote with voter_role snapshot
  ├── Counts approvals
  └── If approvals >= quorum:
      ├── Sets request status = APPROVED
      └── Inserts membership (ACTIVE, role = MEMBER)
```

## Visibility Matrix

| Group kind | `visibility` | In suggestions? | How user finds it |
|---|---|---|---|
| Women-only rant (school/college/work) | `LINK_ONLY` | No | Invite link only (WhatsApp, etc.) |
| Other private groups | `LINK_ONLY` | No | Invite link only |
| Public / open discovery | `DISCOVERABLE` | Yes (filtered by tags, country, policy) | Browse / search + request to join |

## Approval Mode Matrix

| `member_count` vs `settings` | Effective rule |
|---|---|
| `member_count < democraticThreshold` (any mode) | All members equal; any 2+ active members can approve; no single-person override |
| `member_count >= democraticThreshold`, `approvalMode = MEMBERS_QUORUM` | Any N active members can approve |
| `member_count >= democraticThreshold`, `approvalMode = ADMINS_ONLY` | Only OWNER / ADMIN can approve |
| `member_count >= democraticThreshold`, `approvalMode = HYBRID` and below `memberApprovalMaxGroupSize` | Any N active members can approve |
| `member_count >= democraticThreshold`, `approvalMode = HYBRID` and above `memberApprovalMaxGroupSize` | Falls back to `largeGroupApprovalMode` (typically ADMINS_ONLY) |

## Removal Flow

| `member_count` vs `settings` | Effective rule |
|---|---|
| `member_count < democraticThreshold` | Requester + 1 other member (quorum = 2, cannot be lowered) |
| `member_count >= democraticThreshold` | `removalQuorum` from settings (default 2, configurable higher) |
