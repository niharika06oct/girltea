-- ============================================================
-- GirlTea App — Group Entry Questions
-- ============================================================
-- Suggestion incorporated: version column so edits to questions
-- don't orphan old answers.

CREATE TABLE group_entry_questions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id        UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,

    sort_order      INT NOT NULL,
    prompt          TEXT NOT NULL,
    question_type   entry_question_type NOT NULL,
    options         JSONB,
    is_required     BOOLEAN NOT NULL DEFAULT TRUE,

    version         INT NOT NULL DEFAULT 1,

    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_options_for_choice_types
        CHECK (
            (question_type IN ('SINGLE_CHOICE', 'MULTI_CHOICE') AND options IS NOT NULL)
            OR (question_type NOT IN ('SINGLE_CHOICE', 'MULTI_CHOICE'))
        )
);
