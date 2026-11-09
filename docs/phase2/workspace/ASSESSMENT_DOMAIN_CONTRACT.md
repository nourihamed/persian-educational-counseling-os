# Workspace Assessment Domain Contract — Phase 2

**Status:** DRAFT / NOT APPROVED. Domain contract only; no new scoring behavior is approved by this document. Synthetic data only (D-014).

## 1. Scope

This contract covers test definitions, immutable assessment versions, test attempts/responses, analysis, exams and per-subject results. It closes the data-integrity questions raised by WS-DOM-01 and WS-DOM-04 without inventing scoring formulas beyond the Product Owner-approved scoring policy for the relevant assessment.

## 2. Assessment definition and versioning

- `TestDefinition` is the stable identity and metadata (title, subject, grade, test kind, owner, lifecycle).
- `TestDefinitionVersion` is an immutable snapshot of question set/blueprint, question count, topic mapping, time limit and scoring-policy snapshot.
- Publishing a version makes its content and scoring policy immutable. Corrections create a new version; old attempts remain bound to the version they used.
- Every attempt references exactly one published definition version. It must not read current mutable definition fields to reconstruct historical scoring.
- If question delivery is adaptive/randomized, the attempt stores the exact delivered question IDs/order and a hash/snapshot. The attempt's authoritative question count is the delivered set, not a later recomputation from the definition.

## 3. Attempt lifecycle and answer integrity

Canonical lifecycle:
`started → submitted → analysed`, with cancellation permitted only before submission under a separately audited reason.

- A started attempt may have partial responses.
- Each question may have at most one effective response per attempt. Corrections before submission must be versioned/audited or explicitly update the draft response under the attempt's transaction boundary.
- At submission, every delivered question must be represented exactly once as correct, wrong or blank. Blank is an explicit response state, not a missing row.
- The final attempt counters must equal the grouped response counts, and correct + wrong + blank must equal the attempt's authoritative question_count.
- Submission is an atomic finalization boundary. A count mismatch rejects the entire submission; the attempt remains started and can be corrected.
- After submission, question set, responses, counters and scoring-policy snapshot are immutable. Analysis creates a separate versioned result; it must not rewrite the submitted attempt.
- Duplicate submit requests are idempotent. Same idempotency key with a different payload is rejected.

## 4. Scoring and explainability

- Each attempt stores a versioned scoring-policy snapshot: algorithm key/version, negative-marking mode, numerator/denominator semantics, treatment of blank answers, valid-question denominator, rounding mode and precision.
- The exact scoring formula comes from the approved policy for that assessment/exam; no generic formula is silently applied to all tests.
- Scoring is deterministic and reproducible from the immutable response set and policy snapshot. The server computes it through a pure, versioned domain function; persisted output records the algorithm version and input/result hash.
- The database enforces response/count integrity. The service-level test suite must independently recompute the score and compare it to the persisted score. If database-side score validation is later added, it must use the same versioned rule contract, not a hard-coded assumption.
- Negative marking defaults to ON only where the relevant Product Owner decision applies; an exam/test may carry an explicit approved override. The snapshot records the effective setting used for that attempt.
- Analysis records include reason categories and topic-level evidence; an unexplained aggregate score is insufficient.

## 5. Error analysis

- Error reasons support the approved standard taxonomy (concept, memory, careless, time, strategy, unknown) plus a custom reason.
- A custom reason requires a non-empty normalized description and remains linked to the exact response/attempt.
- Analysis may group reasons but must preserve original response-level evidence.
- A later reclassification is a new analysis event/version, not a silent mutation of submitted responses.

## 6. Exam model

- An exam has a stable identity and one or more immutable exam definition/policy snapshots.
- One student exam result may have an aggregate result plus zero or more per-subject result rows.
- Per-subject results are keyed to the exact exam/student/subject and store correct, wrong, blank, valid question count, score and scoring-policy snapshot.
- Aggregate results must reconcile with subject-level totals when subject-level rows are required by the exam blueprint.
- Negative-marking mode and score policy are snapshotted per exam result; later policy changes do not rewrite historical results.

## 7. Required schema structures

The schema design should include or explicitly map:
- `test_definitions` stable identity;
- `test_definition_versions` immutable published version and question blueprint;
- `test_attempts` referencing exact version, authoritative question_count, state, idempotency and immutable scoring snapshot;
- `test_attempt_questions` or equivalent exact delivered question set for adaptive tests;
- `test_responses` one row per delivered question with explicit correct/wrong/blank state and custom error reason support;
- `test_analysis_versions` or append-only analysis events;
- `exams`, `exam_definition_versions`, aggregate `exam_results` and `exam_subject_results`.

Use composite foreign keys to ensure attempt/version/test and exam/student/subject relationships agree. Keep all records Workspace-local and student-scoped.

## 8. Required acceptance tests

1. Attempt cannot submit until all delivered questions have exactly one response, including explicit blanks.
2. Correct/wrong/blank response counts equal attempt counters and question_count at submission.
3. Duplicate question response and wrong attempt/version linkage reject.
4. Submission count mismatch rolls back all finalization changes.
5. Submitted response/question/scoring snapshot cannot be changed or deleted by runtime roles.
6. Definition version publication is immutable; a new version does not alter existing attempts.
7. Adaptive attempt stores exact delivered set; changing the definition later does not change the attempt denominator.
8. Same idempotency key/same payload replays; same key/different payload rejects.
9. Score recomputes deterministically from response set and policy version, including negative-marking ON/OFF and blank cases.
10. Custom error reason requires a description and is preserved through analysis.
11. Exam per-subject results reconcile with aggregate result where blueprint requires it.
12. A test/exam policy change after attempt submission does not alter historical score.
13. Cross-Workspace/cross-student access to definitions, attempts, responses, analysis and exam results is denied by object-level authorization.

All tests remain specifications until executable schema/service tests are implemented and run.

## 9. Open policy inputs

- Exact scoring formula variants and rounding rules beyond already accepted exam rules.
- Whether every assessment type requires per-subject results.
- Whether adaptive question delivery is in MVP or a later feature; the schema should not preclude it.
- Who may correct a response before submission and how corrections are audited.
- Whether analysis can be rerun and how version selection is exposed.

No unapproved scoring formula or product behavior is invented here.

**Gate impact:** WS-DOM-01 and WS-DOM-04 remain open until the current schema is reconciled with this contract and the required integrity tests pass. Phase 2 remains NOT READY.
