-- ============================================================
-- GirlTea App — Group Memberships
-- ============================================================

CREATE TABLE group_memberships (
    group_id    UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    role        membership_role NOT NULL DEFAULT 'MEMBER',
    status      membership_status NOT NULL DEFAULT 'ACTIVE',

    joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (group_id, user_id)
);
