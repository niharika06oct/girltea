-- ============================================================
-- GirlTea App — Enum Types
-- ============================================================

CREATE TYPE gender AS ENUM (
    'WOMAN',
    'MAN',
    'NON_BINARY',
    'GENDERFLUID',
    'AGENDER',
    'GENDERQUEER',
    'QUESTIONING',
    'SELF_DESCRIBE',
    'PREFER_NOT_TO_SAY'
);

CREATE TYPE employment_status AS ENUM (
    'WORKING',
    'NOT_WORKING',
    'PREFER_NOT_TO_SAY'
);

CREATE TYPE group_policy AS ENUM (
    'WOMEN_ONLY',
    'MIXED',
    'GENDER_NEUTRAL'
);

CREATE TYPE group_visibility AS ENUM (
    'LINK_ONLY',
    'DISCOVERABLE'
);

CREATE TYPE approval_mode AS ENUM (
    'MEMBERS_QUORUM',
    'ADMINS_ONLY',
    'HYBRID'
);

CREATE TYPE join_request_status AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED',
    'EXPIRED',
    'CANCELLED'
);

CREATE TYPE join_request_source AS ENUM (
    'INVITE_LINK',
    'SUGGESTION',
    'MANUAL_SEARCH'
);

CREATE TYPE membership_role AS ENUM (
    'OWNER',
    'ADMIN',
    'MEMBER'
);

CREATE TYPE membership_status AS ENUM (
    'ACTIVE',
    'BANNED',
    'LEFT'
);

CREATE TYPE entry_question_type AS ENUM (
    'SHORT_TEXT',
    'LONG_TEXT',
    'SINGLE_CHOICE',
    'MULTI_CHOICE'
);

CREATE TYPE vote_decision AS ENUM (
    'APPROVE',
    'REJECT'
);

CREATE TYPE removal_request_status AS ENUM (
    'PENDING',
    'APPROVED',
    'REJECTED',
    'EXPIRED',
    'CANCELLED'
);

CREATE TYPE report_target_type AS ENUM (
    'POST',
    'COMMENT',
    'USER',
    'GROUP'
);
