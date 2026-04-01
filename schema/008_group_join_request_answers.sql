-- ============================================================
-- GirlTea App — Join Request Answers (to entry questions)
-- ============================================================
-- Suggestion incorporated: reference question_version so answers
-- stay linked to the exact question revision they responded to.

CREATE TABLE group_join_request_answers (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    join_request_id     UUID NOT NULL REFERENCES group_join_requests(id) ON DELETE CASCADE,
    question_id         UUID NOT NULL REFERENCES group_entry_questions(id),

    question_version    INT NOT NULL DEFAULT 1,
    answer_text         TEXT NOT NULL,

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
