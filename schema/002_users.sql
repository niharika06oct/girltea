-- ============================================================
-- GirlTea App — Users (Profile)
-- ============================================================
-- Suggestion incorporated: dateOfBirth instead of raw int age
-- (avoids drift; derive age in queries).
-- Suggestion incorporated: isDeleted + deletedAt for soft-delete
-- (supports "delete my account" + 30-day PII purge job).
-- Suggestion incorporated: createdAt / updatedAt / deletedAt
-- audit trail for GDPR / DPDP compliance.

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    auth_subject    TEXT NOT NULL UNIQUE,

    display_name    TEXT NOT NULL,
    date_of_birth   DATE NOT NULL,
    gender          gender,
    gender_self_describe TEXT,

    employment_status employment_status NOT NULL DEFAULT 'PREFER_NOT_TO_SAY',
    profession      TEXT,

    locale          TEXT NOT NULL DEFAULT 'en-IN',
    country_code    TEXT NOT NULL DEFAULT 'IN',

    in_app_alias    TEXT,
    karma           INT NOT NULL DEFAULT 0,

    is_deleted      BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ,

    CONSTRAINT chk_gender_self_describe
        CHECK (
            (gender = 'SELF_DESCRIBE' AND gender_self_describe IS NOT NULL)
            OR (gender != 'SELF_DESCRIBE')
            OR (gender IS NULL)
        ),

    CONSTRAINT chk_profession_when_working
        CHECK (
            (employment_status = 'WORKING' AND profession IS NOT NULL)
            OR (employment_status != 'WORKING')
        ),

    CONSTRAINT chk_deleted_consistency
        CHECK (
            (is_deleted = TRUE AND deleted_at IS NOT NULL)
            OR (is_deleted = FALSE AND deleted_at IS NULL)
        ),

    CONSTRAINT chk_date_of_birth_minimum_age
        CHECK (date_of_birth <= CURRENT_DATE - INTERVAL '13 years')
);
