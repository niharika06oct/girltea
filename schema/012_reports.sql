-- ============================================================
-- GirlTea App — Reports & Moderation Workflow
-- ============================================================
-- A report is not a flat "resolved yes/no" flag. As an intermediary
-- under India's IT Rules (grievance-officer + takedown-timeline
-- obligations), we need: a typed reason for triage, a status
-- lifecycle, an evidence snapshot preserved at report time (the
-- reported content can be soft-deleted or edited before review),
-- and an append-only action log for the audit trail.

CREATE TABLE reports (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target_type         report_target_type NOT NULL,
    target_id           UUID NOT NULL,

    -- The group the reported content lives in, when resolvable. Lets
    -- moderators scope work per group and preserves context even if the
    -- target is later hard-deleted. NULL for USER reports with no group.
    group_id            UUID REFERENCES groups(id) ON DELETE SET NULL,

    reporter_user_id    UUID NOT NULL REFERENCES users(id),

    reason              report_reason NOT NULL,
    details             TEXT,                       -- reporter's free-text context

    -- Evidence preserved at report time. The reported post/comment can be
    -- soft-deleted or edited before a moderator looks; this JSONB freezes
    -- what was actually reported (body, media_url, author snapshot, etc.).
    evidence            JSONB NOT NULL DEFAULT '{}'::jsonb,

    status              report_status NOT NULL DEFAULT 'PENDING',

    -- Moderator currently handling this report (NULL until picked up).
    assigned_to_user_id UUID REFERENCES users(id),

    resolution_note     TEXT,                       -- final disposition summary
    resolved_at         TIMESTAMPTZ,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_report_resolved_consistency
        CHECK (
            (status IN ('ACTIONED', 'DISMISSED') AND resolved_at IS NOT NULL)
            OR (status IN ('PENDING', 'UNDER_REVIEW') AND resolved_at IS NULL)
        )
);


-- ============================================================
-- Moderation action log — append-only audit trail
-- ============================================================
-- Every moderator touch on a report is recorded here: who did what,
-- when, and why. Never updated or deleted — evidence preservation.

CREATE TABLE report_actions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id           UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,

    actor_user_id       UUID NOT NULL REFERENCES users(id),
    action              moderation_action NOT NULL,
    note                TEXT,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
