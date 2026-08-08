-- ============================================================
-- GirlTea App — Group Memberships
-- ============================================================

CREATE TABLE group_memberships (
    group_id    UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    role        membership_role NOT NULL DEFAULT 'MEMBER',
    status      membership_status NOT NULL DEFAULT 'ACTIVE',

    alias       TEXT NOT NULL,

    -- Gender snapshotted at admission time from users.gender. The
    -- gender-policy guarantee (e.g. WOMEN_ONLY) is evaluated once, when
    -- the member is admitted, and frozen here. Reading users.gender live
    -- would let a later profile edit silently break the guarantee — an
    -- admitted member editing their gender does NOT retroactively
    -- invalidate their membership, and cannot be used to sneak into a
    -- room they wouldn't qualify for today. NULL for pre-existing rows.
    gender_at_admission gender,

    joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (group_id, user_id),

    CONSTRAINT uq_alias_per_group UNIQUE (group_id, alias)
);
