-- =============================================================================
-- CURRICULUM HIERARCHY — SUBTOPICS AND DELETION BEHAVIOUR (SYNTHETIC ONLY, D-014).
-- Run after workspace_schema_draft.sql. No roles are required: these are schema-level assertions.
--
-- SCOPE
--   `CURRICULUM_DOMAIN_CONTRACT.md` is marked DRAFT / NOT APPROVED and its canonical hierarchy is
--   Grade -> Subject -> Book/Edition -> Chapter -> Topic -> Subtopic. The Product Owner decided on
--   2026-11-15 to build **subtopics only**. Book/Edition, curriculum successor mapping and
--   subtopic-level mastery are NOT built and are NOT tested here; they are WS-DOM-05 in the
--   unresolved-item register. These tests therefore cover the one level that was added, plus the
--   deletion-restriction rule that applies to the curriculum nodes that already existed.
--
-- WHAT THESE TESTS DO NOT PROVE
--   Nothing about platform-versus-Workspace content ownership, licensing, curriculum versioning or
--   cross-Workspace isolation of custom curriculum. Those need the structures WS-DOM-05 covers.
-- =============================================================================
\set ON_ERROR_STOP on

CREATE FUNCTION cur_err(p_label text, p_sql text, p_sqlstate text, p_needle text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql AS $fn$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> p_sqlstate THEN
      RAISE EXCEPTION 'FAIL % expected SQLSTATE % but got % (%)', p_label, p_sqlstate, SQLSTATE, SQLERRM;
    END IF;
    IF p_needle IS NOT NULL AND position(p_needle IN SQLERRM) = 0 THEN
      RAISE EXCEPTION 'FAIL % right SQLSTATE, wrong reason: %', p_label, SQLERRM;
    END IF;
    RAISE NOTICE 'PASS %', p_label;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL % statement unexpectedly succeeded', p_label;
END $fn$;

-- Fixture: one chain of the hierarchy that exists today.
INSERT INTO subjects(subject_id,subject_key,title,grade_key,source_kind,source_ref,status)
VALUES ('c1000000-0000-0000-0000-000000000001','biology_10','Biology','grade_10','workspace_custom',NULL,'active');
INSERT INTO chapters(chapter_id,subject_id,title,order_no)
VALUES ('c2000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','Cell Biology',1);
INSERT INTO topics(topic_id,chapter_id,title,order_no)
VALUES ('c3000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000001','Cell Membrane',1),
       ('c3000000-0000-0000-0000-000000000002','c2000000-0000-0000-0000-000000000001','Mitochondria',2);

-- ---------------------------------------------------------------------------------------------------
-- CUR-01..03  The level exists and belongs to exactly one topic.
-- ---------------------------------------------------------------------------------------------------
INSERT INTO subtopics(subtopic_id,topic_id,title,order_no)
VALUES ('c4000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000001','Passive transport',1),
       ('c4000000-0000-0000-0000-000000000002','c3000000-0000-0000-0000-000000000001','Active transport',2);
DO $t$
BEGIN
  IF (SELECT count(*) FROM subtopics WHERE topic_id='c3000000-0000-0000-0000-000000000001') <> 2 THEN
    RAISE EXCEPTION 'FAIL CUR-01 the subtopic rows did not land';
  END IF;
  RAISE NOTICE 'PASS CUR-01 a topic carries ordered subtopics';
END $t$;

SELECT cur_err('CUR-02 a subtopic cannot reference a topic that does not exist',
 $q$INSERT INTO subtopics(subtopic_id,topic_id,title,order_no)
    VALUES (gen_random_uuid(),'c3000000-0000-0000-0000-0000000000ff','Orphan',1)$q$,
 '23503');

SELECT cur_err('CUR-03 two subtopics of one topic cannot share an order number',
 $q$INSERT INTO subtopics(subtopic_id,topic_id,title,order_no)
    VALUES (gen_random_uuid(),'c3000000-0000-0000-0000-000000000001','Duplicate order',1)$q$,
 '23505');

-- The same order number under a DIFFERENT topic is fine: ordering is scoped to the parent.
INSERT INTO subtopics(subtopic_id,topic_id,title,order_no)
VALUES ('c4000000-0000-0000-0000-000000000003','c3000000-0000-0000-0000-000000000002','Electron transport',1);
DO $t$
BEGIN
  RAISE NOTICE 'PASS CUR-04 order numbers are scoped to the parent topic, not global';
END $t$;

-- ---------------------------------------------------------------------------------------------------
-- CUR-05..06  Shape rules. Titles and order numbers are display metadata, so they are constrained for
--             sanity rather than treated as identity.
-- ---------------------------------------------------------------------------------------------------
SELECT cur_err('CUR-05 a blank subtopic title is refused',
 $q$INSERT INTO subtopics(subtopic_id,topic_id,title,order_no)
    VALUES (gen_random_uuid(),'c3000000-0000-0000-0000-000000000002','   ',9)$q$,
 '23514');
SELECT cur_err('CUR-06 a non-positive order number is refused',
 $q$INSERT INTO subtopics(subtopic_id,topic_id,title,order_no)
    VALUES (gen_random_uuid(),'c3000000-0000-0000-0000-000000000002','Zeroth',0)$q$,
 '23514');

-- ---------------------------------------------------------------------------------------------------
-- CUR-07..09  DELETION BEHAVIOUR. The contract requires that a referenced curriculum node be archived
--             and its references preserved, never deleted out from under them. There is no ON DELETE
--             action anywhere in this schema, so the foreign keys restrict by default — CUR-09 asserts
--             that from the catalog rather than trusting it.
-- ---------------------------------------------------------------------------------------------------
SELECT cur_err('CUR-07 a topic that has subtopics cannot be deleted',
 $q$DELETE FROM topics WHERE topic_id='c3000000-0000-0000-0000-000000000001'$q$,
 '23503');

-- Archiving is the supported route, and it leaves the children in place.
UPDATE subtopics SET status='archived' WHERE subtopic_id='c4000000-0000-0000-0000-000000000002';
DO $t$
BEGIN
  IF (SELECT status FROM subtopics WHERE subtopic_id='c4000000-0000-0000-0000-000000000002') <> 'archived' THEN
    RAISE EXCEPTION 'FAIL CUR-08 the subtopic was not archived';
  END IF;
  IF (SELECT count(*) FROM subtopics WHERE topic_id='c3000000-0000-0000-0000-000000000001') <> 2 THEN
    RAISE EXCEPTION 'FAIL CUR-08 archiving removed a row instead of marking it';
  END IF;
  RAISE NOTICE 'PASS CUR-08 a subtopic is archived in place, preserving references';
END $t$;

DO $t$
DECLARE v_bad text;
BEGIN
  -- Any FK in this schema with a non-default delete action would silently destroy history.
  SELECT string_agg(c.relname || '.' || k.conname, ', ')
    INTO v_bad
    FROM pg_constraint k
    JOIN pg_class c ON c.oid = k.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND k.contype = 'f' AND k.confdeltype <> 'a';   -- 'a' = NO ACTION
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CUR-09 these foreign keys do not restrict deletion: %. A cascade or set-null '
                    'would destroy educational history that the curriculum contract requires be preserved.',
                    v_bad;
  END IF;
  RAISE NOTICE 'PASS CUR-09 every foreign key in the Workspace schema restricts deletion (no cascade, no set-null)';
END $t$;

-- ---------------------------------------------------------------------------------------------------
-- CUR-10  What is NOT here. This assertion exists so the absence is explicit and dated rather than
--         looking like an oversight: Book/Edition and curriculum successor mapping are WS-DOM-05.
-- ---------------------------------------------------------------------------------------------------
DO $t$
BEGIN
  IF to_regclass('public.curriculum_books') IS NOT NULL
     OR to_regclass('public.curriculum_book_editions') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CUR-10 book/edition tables exist, so this test and the register entry WS-DOM-05 '
                    'are out of date — update both rather than deleting this assertion';
  END IF;
  RAISE NOTICE 'PASS CUR-10 Book/Edition and successor mapping are absent, as scoped by the Product Owner '
               'on 2026-11-15; tracked as WS-DOM-05, not claimed as done';
END $t$;

DROP FUNCTION cur_err(text,text,text,text);
SELECT 'CURRICULUM TESTS COMPLETED (CUR-01..CUR-10)' AS result;
