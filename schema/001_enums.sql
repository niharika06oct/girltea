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

-- Why the content was reported. Drives triage priority and, under
-- India's IT Rules, the takedown-timeline bucket a report falls into.
CREATE TYPE report_reason AS ENUM (
    'SPAM',
    'HARASSMENT',
    'HATE_SPEECH',
    'VIOLENCE_OR_THREAT',
    'SEXUAL_CONTENT',
    'CSAM',                  -- child sexual abuse material (highest priority)
    'NON_CONSENSUAL_IMAGERY',
    'SELF_HARM',
    'MISINFORMATION',
    'PRIVACY_VIOLATION',     -- doxxing, sharing someone's private info
    'IMPERSONATION',
    'DEFAMATION',
    'OTHER'
);

-- Lifecycle of a report through moderation.
CREATE TYPE report_status AS ENUM (
    'PENDING',        -- newly filed, not yet triaged
    'UNDER_REVIEW',   -- a moderator has picked it up
    'ACTIONED',       -- content/user was acted on
    'DISMISSED'       -- reviewed, no action warranted
);

-- What a moderator did — recorded in the action log for an audit trail.
CREATE TYPE moderation_action AS ENUM (
    'ASSIGNED',
    'CONTENT_REMOVED',
    'CONTENT_KEPT',
    'USER_WARNED',
    'USER_BANNED',
    'ESCALATED',
    'DISMISSED',
    'NOTE'
);
