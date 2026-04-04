-- ============================================================
-- GirlTea App — Groups
-- ============================================================
-- Suggestion incorporated: visibility as enum (LINK_ONLY, DISCOVERABLE)
--   so future values like PUBLIC_SUGGESTED don't need a migration.
-- Suggestion incorporated: memberCount maintained via trigger for
--   race-condition-safe monotonic updates.
-- Suggestion incorporated: JSON settings with partial indexes on
--   commonly queried fields.

CREATE TABLE groups (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name                TEXT NOT NULL,
    description         TEXT,

    policy              group_policy NOT NULL,
    visibility          group_visibility NOT NULL,

    category_tags       TEXT[] NOT NULL DEFAULT '{}',

    created_by_user_id  UUID NOT NULL REFERENCES users(id),

    member_count        INT NOT NULL DEFAULT 0,

    settings            JSONB NOT NULL DEFAULT '{
        "approvalMode": "HYBRID",
        "memberApproverQuorum": 2,
        "memberApprovalMaxGroupSize": 20,
        "largeGroupApprovalMode": "ADMINS_ONLY",
        "joinRequestTtlHours": 336,
        "allowInviteLink": true,
        "removalQuorum": 2,
        "removalRequestTtlHours": 168,
        "democraticThreshold": 10
    }'::jsonb,

    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ,

    CONSTRAINT chk_member_count_non_negative
        CHECK (member_count >= 0),

    CONSTRAINT chk_group_deleted_consistency
        CHECK (
            (is_deleted = TRUE AND deleted_at IS NOT NULL)
            OR (is_deleted = FALSE AND deleted_at IS NULL)
        )
);
