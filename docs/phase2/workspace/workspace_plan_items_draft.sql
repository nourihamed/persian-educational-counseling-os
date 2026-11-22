-- WORKSPACE DB — DRAFT: the normalized PlanItem DATA MODEL (WS-PLAN-01, Product Owner decision Option B,
-- 2026-11-18, recorded in DECISION_LOG.md and the unresolved-item register). Synthetic only (D-014).
-- NOT a migration. Apply AFTER workspace_transfer_freeze.sql (write barrier) and
-- workspace_counselor_scope_draft.sql (counselor boundary), BEFORE workspace_roles_setup_draft.sql.
--
-- WHAT THE DECISION APPROVED, AND THEREFORE WHAT IS BUILT
--   * Each PlanItem references EXACTLY ONE source, through typed nullable foreign keys — `topic`,
--     `subtopic`, `activity`, `exam`, `review`, `assignment` — with an exactly-one-source CHECK. No
--     `source_type/source_id`.
--   * Status vocabulary: planned, in_progress, completed, partially_completed, deferred, skipped, cancelled.
--   * Deferral reasons: insufficient_time, schedule_conflict, prerequisite_not_mastered, difficulty,
--     illness_or_absence, resource_unavailable, higher_priority_task, student_requested,
--     counselor_adjustment, other. `deferred` requires a reason; `other` MAY carry a note.
--   * Normalized items are authoritative for new plan versions. `plan_content` survives only for legacy
--     versions; it is never a second editable source, and any JSON for output is DERIVED from the items.
--   * Published versions stay immutable. Item changes and status transitions are auditable with actor,
--     timestamp and reason.
--
-- HOW "AUDITABLE" AND "IMMUTABLE" ARE RECONCILED
--   A plan item's DEFINITION (what, when, for how long) is insert-only: it cannot be updated or deleted,
--   even in a draft, because a draft that can be silently rewritten has no history. A change to a plan is
--   a NEW plan version that names the version it supersedes and states why — the master prompt's "Week 1
--   Plan v1, v2, v3", and the contract's "adjustments create a new version with a parent/supersedes
--   reference and a reason". Items may be ADDED to a version only while it is a draft.
--   An item's EXECUTION STATUS changes over time, including on a published version. It therefore lives in
--   an append-only event table, one row per transition with actor, timestamp and reason; the current
--   status is derived, never stored twice. Two concurrent transitions from the same state cannot both
--   succeed: each event carries the next sequence number and (plan_item_id, seq_no) is unique.
--
-- WHAT IS DELIBERATELY NOT BUILT (no decision covers it; each listed so nobody infers it)
--   * NO scheduling logic, ranking, conflict detection, generation or replay (Phase 12, as decided).
--   * No priority, urgency, estimated workload scale, dependencies, conflict groups, generation
--     provenance, idempotency key or carry-forward link — the contract lists them, the decision did not
--     settle their vocabularies, and contract §9 forbids inventing weights or thresholds.
--   * No Product Owner-approved from_status -> to_status graph. Decisions A2/B1/C1/D1/E1 settle actor
--     categories, draft publication state, empty publication, terminal destinations and legacy read-only
--     semantics, but do not approve exact edges. The base schema therefore creates an EMPTY
--     plan_item_transition_rules table: every edge fails closed until a separate PO decision and reviewed
--     migration populate it. Test suites seed disposable test-only edges solely to exercise guard mechanics;
--     those fixtures are not production policy and are not evidence that the PO approved those edges.
--     A transition TO planned, counselor recording a student status, and student recording a counselor
--     status remain explicitly refused. Whether a student may edit generated items (contract §9) is open.
--   * Engine-created items will need a non-membership actor; none exists until Phase 12.
--
-- CORRECTED AFTER THE SUPERVISOR REVIEW OF 8df7d5e (2026-11-19), FINDING F-05 (HIGH): the privileged
-- identities are checked by IDENTITY, not membership. See plan_identity_is() and
-- plan_identity_boundary_violations(); tests in tests/workspace_plan_identity_membership_tests.sql (F05-*) and
-- tests/workspace_plan_identity_bootstrap_tests.sh (F05-BOOT-*).
--
-- CORRECTED AFTER THE SUPERVISOR REVIEW OF d75d039 (2026-11-18). FOUR FINDINGS, EACH NOW FAIL-CLOSED
--   F-01 CRITICAL — actor impersonation. As first written, the runtime could INSERT plan items and status
--     transitions, and the actor was whatever the row SAID: actor_kind='student' skipped every check, and a
--     membership id was validated against the counselor boundary but never bound to the caller. Any code
--     path holding the shared runtime role could therefore record a transition "as the student", or as
--     another counselor, for any student. The database cannot authenticate either kind of actor today —
--     that is exactly the WS-ISO-01 caller-binding gap, which needs a Platform Security decision this file
--     does not make. So:
--       - NO application role may insert plan items or status transitions: the runtime holds SELECT only;
--       - actor_kind = 'student' is refused outright, because no student identity can be authenticated;
--       - the only writer is a dedicated NOLOGIN SYNTHETIC test identity (D-014), named in
--         plan_privileged_identities and checked by IDENTITY (current_user, as PostgreSQL sets it; since F-05 not
--         membership) — never by a session variable or GUC, which the caller sets.
--     A membership id on a row remains ATTRIBUTION, not proof of who wrote it.
--   F-02 HIGH — new legacy_json versions were creatable by the runtime. Now the runtime may not even name
--     content_model (column-level INSERT privilege excludes it, so every runtime-created version is
--     normalized), and a legacy_json insert is accepted only from the dedicated NOLOGIN migration identity.
--   F-03 MEDIUM — open semantics were permissive. Publishing an EMPTY normalized version and recording
--     status on a DRAFT version's items are now refused, pending Product Owner decisions; the refusal says
--     so. No transition graph is invented.
--   F-04 MEDIUM — the backfill. Adding the column with DEFAULT 'normalized' would have classified every
--     historical row as normalized and the empty-JSON CHECK would then have failed on any real history.
--     Existing rows are now classified legacy_json at the moment the column is added; only rows created
--     afterwards default to normalized. See WS_PLAN_01_MIGRATION_NOTES.md and PLN-M01..M08.
BEGIN;

-- ======================================================================================================
-- 1. Plan versions: content model, supersession and actor
-- ======================================================================================================
-- Added here rather than in workspace_schema_draft.sql so suites that do not load this file keep their
-- legacy fixtures; in this file's databases every NEW version is normalized by default.
-- F-04: every row that exists when this runs is HISTORICAL, so it is classified legacy_json; only rows created
-- afterwards default to normalized (the SET DEFAULT below). PostgreSQL fills the new column for existing rows
-- from the DEFAULT given in ADD COLUMN, and the CHECK is validated against those rows in the same statement —
-- so with DEFAULT 'normalized' here, any historical row whose plan_content is not '{}' would make this
-- statement fail, and one whose content happened to be '{}' would silently become "normalized" with no items.
ALTER TABLE student_plan_versions
  ADD COLUMN content_model text NOT NULL DEFAULT 'legacy_json'
    CHECK (content_model IN ('normalized','legacy_json')),
  ADD COLUMN supersedes_plan_version_id uuid REFERENCES student_plan_versions(plan_version_id),
  ADD COLUMN change_reason text,
  ADD COLUMN created_by_membership_id uuid REFERENCES workspace_memberships(membership_id),
  -- One source of truth: a normalized version's plan_content carries nothing. Output JSON is derived
  -- (plan_version_rendered, below), so there is no second document to keep in step.
  ADD CONSTRAINT normalized_version_has_no_json_content
    CHECK (content_model <> 'normalized' OR plan_content = '{}'::jsonb);
ALTER TABLE student_plan_versions ALTER COLUMN content_model SET DEFAULT 'normalized';
ALTER TABLE student_plan_versions
  ADD CONSTRAINT student_plan_versions_id_plan_key UNIQUE (plan_version_id, plan_id);

-- ======================================================================================================
-- 0. The privileged identities, by ROLE, verified by PostgreSQL (F-01, F-02)
-- ======================================================================================================
-- Written only by the table owner (workspace_roles_setup_draft.sql fills it). A purpose with no row means no
-- identity holds it, and every check below then refuses — fail closed by absence.
CREATE TABLE plan_privileged_identities (
  purpose   text PRIMARY KEY CHECK (purpose IN ('synthetic_plan_writer','legacy_plan_migrator')),
  role_name text NOT NULL,
  note      text NOT NULL
);
-- F-05 (Supervisor review of 8df7d5e): the check is IDENTITY, not membership.
-- The earlier form was pg_has_role(current_user, role, 'MEMBER'). That is true for ANY role holding the
-- privileged role directly or through a chain, with or without INHERIT or SET. A single stray
-- `GRANT writer TO runtime` would therefore have turned the shared runtime into a plan author.
-- Now the session must BE the privileged role (current_user = role), and the role must be in the state the
-- bootstrap requires. That state is re-checked here on every call, so a later change fails closed without
-- waiting for the next bootstrap:
--   * NOLOGIN, NOSUPERUSER, NOCREATEROLE, NOBYPASSRLS, NOREPLICATION, NOCREATEDB, NOINHERIT;
--   * NO pg_auth_members row in either direction. Nobody holds it (so no SET ROLE path exists, whatever the
--     INHERIT/SET/ADMIN options), and it holds nothing.
-- With no members and NOLOGIN, the only way for current_user to become the role is a superuser running
-- SET ROLE or SET SESSION AUTHORIZATION: the isolated synthetic test harness. A superuser is not
-- accepted as itself (current_user is then the superuser's name). A superuser can bypass any in-database
-- control anyway, so who may act as superuser is an operational decision, recorded as open, not one made here.
-- search_path is pinned and every relation is schema-qualified, so a session cannot shadow a catalog or
-- table with a temporary object.
CREATE FUNCTION plan_identity_is(p_purpose text) RETURNS boolean
LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $body$
  SELECT coalesce((
    SELECT r.rolname = current_user
       AND NOT r.rolcanlogin AND NOT r.rolsuper AND NOT r.rolcreaterole AND NOT r.rolbypassrls
       AND NOT r.rolreplication AND NOT r.rolcreatedb AND NOT r.rolinherit
       AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members m WHERE m.roleid = r.oid OR m.member = r.oid)
      FROM public.plan_privileged_identities i
      JOIN pg_catalog.pg_roles r ON r.rolname = i.role_name
     WHERE i.purpose = p_purpose), false);
$body$;

-- F-05: what the bootstrap must establish, as a list of violations (an empty result is the only pass).
-- F-05 follow-up (Supervisor review of 38f2561): owner roles are now checked for TRANSITIVE reach, not only a
-- direct member; every inventory role is checked against its EXPECTED attributes, not a few dangerous ones; and
-- the inventory's memberships must be EXACTLY the three login -> service grants the bootstrap makes.
-- Role classes come from the same rule workspace_roles_setup_draft.sql uses to create the roles:
--   '<...>_owner'  -> owner role:   NOLOGIN, NOINHERIT; holds nothing, held by nothing
--   '<...>_login'  -> login role:   LOGIN, INHERIT; holds exactly its service role '<...>' (no ADMIN), nothing else
--   otherwise      -> service role: NOLOGIN, NOINHERIT; held only by its own login role, holds nothing
-- and every one of them NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS.
-- p_inventory is the Workspace's application role inventory, passed by workspace_roles_setup_draft.sql
-- from its own role list: owners, runtime, worker, exporter and their login identities. It does not
-- exempt anything: the membership checks look at EVERY role in the cluster (pg_auth_members is
-- cluster-wide). A privileged role that cannot be found, or a row that does not resolve, is a violation;
-- nothing unclassified passes.
CREATE FUNCTION plan_identity_boundary_violations(p_inventory text[]) RETURNS SETOF text
LANGUAGE sql STABLE SET search_path = pg_catalog, pg_temp AS $body$
  WITH need(purpose) AS (VALUES ('synthetic_plan_writer'), ('legacy_plan_migrator')),
  priv AS (
    SELECT n.purpose, i.role_name, r.oid, r.rolcanlogin, r.rolsuper, r.rolcreaterole, r.rolbypassrls,
           r.rolreplication, r.rolcreatedb, r.rolinherit
      FROM need n
      LEFT JOIN public.plan_privileged_identities i ON i.purpose = n.purpose
      LEFT JOIN pg_catalog.pg_roles r ON r.rolname = i.role_name),
  guarded(tbl) AS (VALUES ('public.plan_items'), ('public.plan_item_status_events'),
                          ('public.student_plan_versions'), ('public.plan_privileged_identities'),
                          ('public.plan_item_transition_rules')),
  security_functions(sig) AS (VALUES ('public.plan_identity_is(text)'), ('public.guard_plan_item()'),
                          ('public.guard_plan_item_status_event()'), ('public.guard_plan_version_model()'),
                          ('public.plan_identity_boundary_violations(text[])')),
  guard_triggers(tbl, tg) AS (VALUES ('public.plan_items','plan_items_guard'),
                          ('public.plan_item_status_events','plan_item_status_events_guard'),
                          ('public.student_plan_versions','student_plan_versions_model_guard')),
  owners AS (
    SELECT DISTINCT c.relowner AS oid FROM guarded g JOIN pg_catalog.pg_class c ON c.oid = g.tbl::regclass
    UNION SELECT p.proowner FROM security_functions f JOIN pg_catalog.pg_proc p ON p.oid = f.sig::regprocedure
    -- the three Workspace owner roles are owners whether or not they own a plan object today
    UNION SELECT r.oid FROM pg_catalog.pg_roles r WHERE r.rolname = ANY (p_inventory) AND r.rolname LIKE '%\_owner')
  -- the privileged identities themselves
  SELECT format('%s: no privileged identity is recorded', n.purpose)
    FROM need n WHERE NOT EXISTS (SELECT 1 FROM public.plan_privileged_identities i WHERE i.purpose = n.purpose)
  UNION ALL SELECT format('%s: role %s does not exist', purpose, role_name) FROM priv WHERE role_name IS NOT NULL AND oid IS NULL
  UNION ALL SELECT format('%s: role %s has LOGIN', purpose, role_name)       FROM priv WHERE rolcanlogin
  UNION ALL SELECT format('%s: role %s has SUPERUSER', purpose, role_name)   FROM priv WHERE rolsuper
  UNION ALL SELECT format('%s: role %s has CREATEROLE', purpose, role_name)  FROM priv WHERE rolcreaterole
  UNION ALL SELECT format('%s: role %s has BYPASSRLS', purpose, role_name)   FROM priv WHERE rolbypassrls
  UNION ALL SELECT format('%s: role %s has REPLICATION', purpose, role_name) FROM priv WHERE rolreplication
  UNION ALL SELECT format('%s: role %s has CREATEDB', purpose, role_name)    FROM priv WHERE rolcreatedb
  UNION ALL SELECT format('%s: role %s has INHERIT', purpose, role_name)     FROM priv WHERE rolinherit
  UNION ALL SELECT format('%s: role %s is the same role as another privileged identity or an application role', p.purpose, p.role_name)
    FROM priv p WHERE p.role_name = ANY (p_inventory)
       OR EXISTS (SELECT 1 FROM priv q WHERE q.purpose <> p.purpose AND q.role_name = p.role_name)
  -- membership in EITHER direction, whatever the INHERIT / SET / ADMIN options: nobody may hold it, it holds nothing
  UNION ALL SELECT format('%s: role %s is held by %s (admin=%s inherit=%s set=%s)', p.purpose, p.role_name,
                         m.member::regrole, m.admin_option, m.inherit_option, m.set_option)
    FROM priv p JOIN pg_catalog.pg_auth_members m ON m.roleid = p.oid
  UNION ALL SELECT format('%s: role %s is itself a member of %s', p.purpose, p.role_name, m.roleid::regrole)
    FROM priv p JOIN pg_catalog.pg_auth_members m ON m.member = p.oid
  -- a privileged identity owns nothing, in any database of the cluster (it could otherwise alter what it owns)
  UNION ALL SELECT format('%s: role %s owns objects (%s)', p.purpose, p.role_name, count(*))
    FROM priv p JOIN pg_catalog.pg_shdepend d ON d.refobjid = p.oid AND d.deptype = 'o'
   GROUP BY p.purpose, p.role_name
  -- the application inventory: no cluster-level authority, and no path to a privileged identity
  UNION ALL SELECT format('application role %s does not exist', a) FROM unnest(p_inventory) a
   WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname = a)
  UNION ALL SELECT format('application role %s has %s', r.rolname, attr)
    FROM pg_catalog.pg_roles r
    CROSS JOIN LATERAL (VALUES ('SUPERUSER', r.rolsuper), ('CREATEROLE', r.rolcreaterole),
                               ('BYPASSRLS', r.rolbypassrls), ('REPLICATION', r.rolreplication),
                               ('CREATEDB', r.rolcreatedb)) v(attr, val)
   WHERE r.rolname = ANY (p_inventory) AND v.val
  -- expected LOGIN / INHERIT per role class (see above)
  UNION ALL SELECT format('application role %s: expected %s, found %s', r.rolname,
                          CASE WHEN r.rolname LIKE '%\_login' THEN 'LOGIN' ELSE 'NOLOGIN' END,
                          CASE WHEN r.rolcanlogin THEN 'LOGIN' ELSE 'NOLOGIN' END)
    FROM pg_catalog.pg_roles r
   WHERE r.rolname = ANY (p_inventory) AND r.rolcanlogin <> (r.rolname LIKE '%\_login')
  UNION ALL SELECT format('application role %s: expected %s, found %s', r.rolname,
                          CASE WHEN r.rolname LIKE '%\_login' THEN 'INHERIT' ELSE 'NOINHERIT' END,
                          CASE WHEN r.rolinherit THEN 'INHERIT' ELSE 'NOINHERIT' END)
    FROM pg_catalog.pg_roles r
   WHERE r.rolname = ANY (p_inventory) AND r.rolinherit <> (r.rolname LIKE '%\_login')
  -- the inventory's memberships are EXACTLY '<x>_login' holding '<x>', without ADMIN, for each service role;
  -- any other row with an inventory role on either side is unexpected, whatever its options
  UNION ALL SELECT format('unexpected membership: %s holds %s (admin=%s inherit=%s set=%s)',
                          m.member::regrole, m.roleid::regrole, m.admin_option, m.inherit_option, m.set_option)
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles rm ON rm.oid = m.member
    JOIN pg_catalog.pg_roles rr ON rr.oid = m.roleid
   WHERE (rm.rolname = ANY (p_inventory) OR rr.rolname = ANY (p_inventory))
     AND NOT (rm.rolname = ANY (p_inventory) AND rr.rolname = ANY (p_inventory)
              AND rm.rolname LIKE '%\_login' AND rr.rolname NOT LIKE '%\_owner'
              AND rr.rolname = left(rm.rolname, length(rm.rolname) - 6)
              AND NOT m.admin_option)
  -- TRANSITIVE reach: walk every membership chain upward from every inventory role, whatever the
  -- INHERIT / SET / ADMIN options of each link (a link without SET still lets an ADMIN holder re-grant, and
  -- options can be changed later by whoever can grant), and report any chain that ends at a privileged
  -- identity or at an owner role (the three inventory owners and the actual owners of the security objects)
  UNION ALL
  SELECT format('application role %s can reach %s %s via %s', w.start_name,
                CASE WHEN EXISTS (SELECT 1 FROM priv p WHERE p.oid = w.roleid) THEN 'privileged identity' ELSE 'owner' END,
                w.roleid::regrole,
                (SELECT string_agg(x::regrole::text, ' -> ' ORDER BY o) FROM unnest(w.path) WITH ORDINALITY u(x, o)))
    FROM (
      WITH RECURSIVE up(start_name, roleid, path) AS (
        SELECT r.rolname::text, m.roleid, ARRAY[r.oid, m.roleid]
          FROM pg_catalog.pg_roles r JOIN pg_catalog.pg_auth_members m ON m.member = r.oid
         WHERE r.rolname = ANY (p_inventory)
        UNION ALL
        SELECT u.start_name, m.roleid, u.path || m.roleid
          FROM up u JOIN pg_catalog.pg_auth_members m ON m.member = u.roleid
         WHERE NOT m.roleid = ANY (u.path))
      SELECT * FROM up) w
   WHERE EXISTS (SELECT 1 FROM priv p WHERE p.oid = w.roleid)
      OR w.roleid IN (SELECT o.oid FROM owners o)
      OR w.roleid IN (SELECT r.oid FROM pg_catalog.pg_roles r
                       WHERE r.rolname = ANY (p_inventory) AND r.rolname LIKE '%\_owner')
  -- whoever owns the guarded tables and security functions can disable or replace them, so nobody may hold
  -- an owner role, and an owner is never a privileged identity
  UNION ALL SELECT format('owner %s of the plan security objects is held by %s', o.oid::regrole, m.member::regrole)
    FROM owners o JOIN pg_catalog.pg_auth_members m ON m.roleid = o.oid
  UNION ALL SELECT format('owner %s of the plan security objects is a privileged identity', o.oid::regrole)
    FROM owners o JOIN priv p ON p.oid = o.oid
  UNION ALL SELECT format('owner %s of the plan security objects can log in or has cluster authority', r.rolname)
    FROM owners o JOIN pg_catalog.pg_roles r ON r.oid = o.oid
   WHERE r.rolcanlogin OR r.rolsuper OR r.rolcreaterole OR r.rolbypassrls OR r.rolreplication
  -- the guard triggers exist and are enabled
  UNION ALL SELECT format('guard trigger %s on %s is missing', g.tg, g.tbl) FROM guard_triggers g
   WHERE NOT EXISTS (SELECT 1 FROM pg_catalog.pg_trigger t WHERE t.tgrelid = g.tbl::regclass AND t.tgname = g.tg)
  UNION ALL SELECT format('guard trigger %s on %s is not enabled (tgenabled=%s)', g.tg, g.tbl, t.tgenabled)
    FROM guard_triggers g JOIN pg_catalog.pg_trigger t ON t.tgrelid = g.tbl::regclass AND t.tgname = g.tg
   WHERE t.tgenabled NOT IN ('O','A')
  -- no alternate write path: no non-owner application role, and not PUBLIC, may write the identity record or
  -- the plan tables (column privileges included). student_plan_versions is excluded here on purpose: the
  -- runtime's column-scoped INSERT on it is intended (F-02) and asserted by PLN-C2/PLN-28.
  UNION ALL SELECT format('%s holds %s on %s', a, priv_name, t.tbl)
    FROM unnest(p_inventory || ARRAY['public']) a
    CROSS JOIN (VALUES ('public.plan_items'), ('public.plan_item_status_events'), ('public.plan_privileged_identities'),
                         ('public.plan_item_transition_rules')) t(tbl)
    CROSS JOIN (VALUES ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) v(priv_name)
   WHERE (a = 'public' OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname = a))
     AND NOT EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_roles r ON r.oid = c.relowner
                      WHERE c.oid = t.tbl::regclass AND r.rolname = a)
     AND CASE WHEN a = 'public'
              THEN EXISTS (SELECT 1 FROM pg_catalog.pg_class c, LATERAL pg_catalog.aclexplode(c.relacl) x
                            WHERE c.oid = t.tbl::regclass AND x.grantee = 0 AND x.privilege_type = v.priv_name)
              ELSE pg_catalog.has_table_privilege(a, t.tbl, v.priv_name)
                   OR (v.priv_name IN ('INSERT','UPDATE')
                       AND pg_catalog.has_any_column_privilege(a, t.tbl, v.priv_name)) END;
$body$;

CREATE FUNCTION guard_plan_version_model() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_prev_plan uuid; v_prev_no integer;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.content_model = 'legacy_json' THEN
    -- Decision E1 (Product Owner, 2026-11-20): legacy JSON plans remain READ-ONLY. A counselor converts one
    -- by creating a NEW normalized version that supersedes it, with a reason; the legacy row never changes.
    RAISE EXCEPTION 'a legacy_json plan version is read-only (decision E1); create a new normalized version '
                    'that supersedes it' USING ERRCODE='check_violation';
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status = 'published' THEN
      RAISE EXCEPTION 'a published PlanVersion is immutable; create a superseding version'
        USING ERRCODE='check_violation';
    END IF;
    -- Publication serializes against PlanItem insertion. The UPDATE already takes a NO KEY UPDATE row
    -- lock; restate the lock here as part of the documented protocol. Item insertion takes FOR SHARE
    -- on this same PlanVersion row before checking its status and inserting the item.
    PERFORM 1 FROM public.student_plan_versions v
      WHERE v.plan_version_id = OLD.plan_version_id FOR NO KEY UPDATE;
    IF (NEW.content_model, NEW.supersedes_plan_version_id, NEW.change_reason, NEW.created_by_membership_id)
       IS DISTINCT FROM
       (OLD.content_model, OLD.supersedes_plan_version_id, OLD.change_reason, OLD.created_by_membership_id) THEN
      RAISE EXCEPTION 'a plan version''s content model, supersession, change reason and author are fixed at '
                      'creation' USING ERRCODE='check_violation';
    END IF;
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      -- The only approved publication transition is normalized draft -> published. Legacy JSON is
      -- read-only (E1), and all other lifecycle edges remain undecided and fail-closed.
      IF OLD.status <> 'draft' OR NEW.status <> 'published' OR NEW.content_model <> 'normalized' THEN
        RAISE EXCEPTION 'only a normalized draft may be published; other PlanVersion status transitions are '
                        'undecided and refused (WS-PLAN-01)' USING ERRCODE='check_violation';
      END IF;
      -- Decision C1: count only after the PlanVersion row lock is held, so an item insert cannot race
      -- between the emptiness check and publication.
      IF NOT EXISTS (SELECT 1 FROM public.plan_items i WHERE i.plan_version_id = NEW.plan_version_id) THEN
        RAISE EXCEPTION 'publishing an EMPTY normalized plan version is prohibited (Product Owner decision '
                        'WS-PLAN-01 C1)' USING ERRCODE='check_violation';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  -- H-02: every newly inserted PlanVersion, including a migration-created legacy row, starts as draft.
  -- Historical rows that predate this trigger are untouched. Publication is a separate guarded UPDATE.
  IF NEW.status <> 'draft' THEN
    RAISE EXCEPTION 'a new PlanVersion must be inserted as draft; direct published insertion is prohibited'
      USING ERRCODE='check_violation';
  END IF;

  IF NEW.content_model = 'legacy_json' THEN
    -- F-02: legacy JSON is for historical compatibility and migration ONLY. A new legacy version is accepted
    -- solely from the dedicated migration identity. The runtime cannot get here at all — it holds no INSERT
    -- privilege on content_model — so this is the second wall, not the first.
    IF NOT public.plan_identity_is('legacy_plan_migrator') THEN
      RAISE EXCEPTION 'a legacy_json plan version can only be written by the migration identity; new plan '
                      'versions are normalized' USING ERRCODE='insufficient_privilege';
    END IF;
    -- Legacy JSON exists for historical compatibility and migration only. Once a plan has a normalized
    -- version, it does not regress to JSON.
    IF EXISTS (SELECT 1 FROM public.student_plan_versions v
                WHERE v.plan_id = NEW.plan_id AND v.content_model = 'normalized') THEN
      RAISE EXCEPTION 'plan % already has a normalized version; a legacy_json version cannot follow it',
        NEW.plan_id USING ERRCODE='check_violation';
    END IF;
    RETURN NEW;
  END IF;

  -- Normalized: attributable, and an adjustment names what it adjusts and why.
  IF NEW.created_by_membership_id IS NULL THEN
    RAISE EXCEPTION 'a normalized plan version must record the membership that created it'
      USING ERRCODE='check_violation';
  END IF;
  IF NEW.version_no > 1 THEN
    IF NEW.supersedes_plan_version_id IS NULL OR coalesce(length(btrim(NEW.change_reason)),0) = 0 THEN
      RAISE EXCEPTION 'plan version % of plan % must name the version it supersedes and the reason for the '
                      'change', NEW.version_no, NEW.plan_id USING ERRCODE='check_violation';
    END IF;
    SELECT v.plan_id, v.version_no INTO v_prev_plan, v_prev_no
      FROM public.student_plan_versions v WHERE v.plan_version_id = NEW.supersedes_plan_version_id;
    IF v_prev_plan IS DISTINCT FROM NEW.plan_id OR v_prev_no >= NEW.version_no THEN
      RAISE EXCEPTION 'a plan version may only supersede an EARLIER version of the SAME plan'
        USING ERRCODE='check_violation';
    END IF;
  ELSIF NEW.supersedes_plan_version_id IS NOT NULL THEN
    RAISE EXCEPTION 'version 1 of a plan supersedes nothing' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER student_plan_versions_model_guard
  BEFORE INSERT OR UPDATE ON student_plan_versions
  FOR EACH ROW EXECUTE FUNCTION guard_plan_version_model();

-- Ownership-bound targets for the composite foreign keys below.
ALTER TABLE student_plans ADD CONSTRAINT student_plans_id_student_key UNIQUE (plan_id, student_id);
CREATE UNIQUE INDEX activities_id_student_key ON activities(activity_id, student_id);

-- ======================================================================================================
-- 2. Plan items — the definition, insert-only
-- ======================================================================================================
CREATE TABLE plan_items (
  plan_item_id       uuid PRIMARY KEY,
  plan_version_id    uuid NOT NULL,
  plan_id            uuid NOT NULL,
  student_id         uuid NOT NULL,
  item_no            integer NOT NULL CHECK (item_no > 0),
  -- exactly one typed source (decision: topic, subtopic, activity, exam, review, assignment)
  topic_id           uuid REFERENCES topics(topic_id),
  subtopic_id        uuid REFERENCES subtopics(subtopic_id),
  activity_id        uuid,
  exam_id            uuid,
  review_id          uuid,
  assignment_id      uuid,
  -- when, in the student's local calendar; the UTC projection is derived, never supplied
  planned_local_date date NOT NULL,
  planned_start_local time,
  planned_minutes    integer CHECK (planned_minutes IS NULL OR planned_minutes > 0),
  timezone_name      text NOT NULL,
  planned_start_utc  timestamptz,
  note               text,
  created_by_membership_id uuid NOT NULL REFERENCES workspace_memberships(membership_id),
  created_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (plan_version_id, item_no),
  UNIQUE (plan_item_id, student_id),
  -- the item belongs to the version, the version to the plan, the plan to the student: one chain
  FOREIGN KEY (plan_version_id, plan_id) REFERENCES student_plan_versions(plan_version_id, plan_id),
  FOREIGN KEY (plan_id, student_id)      REFERENCES student_plans(plan_id, student_id),
  -- student-owned sources are bound to THIS student, so an item cannot schedule another student's work
  FOREIGN KEY (activity_id, student_id)   REFERENCES activities(activity_id, student_id),
  FOREIGN KEY (exam_id, student_id)       REFERENCES exams(exam_id, student_id),
  FOREIGN KEY (review_id, student_id)     REFERENCES reviews(review_id, student_id),
  FOREIGN KEY (assignment_id, student_id) REFERENCES assignments(assignment_id, student_id),
  CONSTRAINT plan_item_exactly_one_source
    CHECK (num_nonnulls(topic_id, subtopic_id, activity_id, exam_id, review_id, assignment_id) = 1),
  CHECK ((planned_start_local IS NULL) = (planned_start_utc IS NULL))
);
CREATE INDEX plan_items_student_date_idx ON plan_items(student_id, planned_local_date);

CREATE FUNCTION guard_plan_item() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_status text; v_model text;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'a plan item is insert-only; change a plan by creating a new plan version that '
                    'supersedes it, with a reason' USING ERRCODE='check_violation';
  END IF;
  -- F-01: created_by_membership_id is what the row CLAIMS. No application identity can be bound to a
  -- membership yet (WS-ISO-01), so no application identity may plan; only the synthetic writer may.
  IF NOT public.plan_identity_is('synthetic_plan_writer') THEN
    RAISE EXCEPTION 'no application identity can be authenticated as a plan author until the WS-ISO-01 '
                    'caller binding exists; plan items are writable only by the synthetic test identity'
      USING ERRCODE='insufficient_privilege';
  END IF;
  -- Shared lock is the other half of the publication protocol: publication's UPDATE/NO KEY UPDATE
  -- lock conflicts with this FOR SHARE. If item insertion wins, publication waits and then sees the item;
  -- if publication wins, this waits and then observes published, refusing the late item.
  SELECT v.status, v.content_model INTO v_status, v_model
    FROM public.student_plan_versions v
   WHERE v.plan_version_id = NEW.plan_version_id
   FOR SHARE;
  IF v_model IS DISTINCT FROM 'normalized' THEN
    RAISE EXCEPTION 'plan items belong only to normalized plan versions; a legacy_json version keeps its '
                    'content in plan_content' USING ERRCODE='check_violation';
  END IF;
  IF v_status IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'items can only be added to a DRAFT plan version; a published version is immutable'
      USING ERRCODE='check_violation';
  END IF;
  -- WS-ISO-01 (decision B): the author named on the row must BE the verified principal of this
  -- transaction. A membership id supplied by the caller is a claim, never proof.
  IF public.current_principal_membership() IS NULL
     OR NEW.created_by_membership_id IS DISTINCT FROM public.current_principal_membership() THEN
    RAISE EXCEPTION 'the plan item author must be the verified principal of this transaction'
      USING ERRCODE='insufficient_privilege';
  END IF;
  IF NOT public.counselor_may_access_student(NEW.created_by_membership_id, NEW.student_id) THEN
    RAISE EXCEPTION 'membership % is not an active, accepted counselor of student %; it cannot plan for '
                    'that student', NEW.created_by_membership_id, NEW.student_id USING ERRCODE='check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = NEW.timezone_name) THEN
    RAISE EXCEPTION 'unknown time zone %', NEW.timezone_name USING ERRCODE='check_violation';
  END IF;
  -- Derived, so it cannot disagree with the local values. PostgreSQL's resolution of a local time that is
  -- ambiguous or skipped at a DST transition is deterministic; whether that rule is the PRODUCT's rule
  -- (contract §8 test 10) is for Phase 12. Iran has observed no DST since 2022, so the case is real only for
  -- other zones.
  NEW.planned_start_utc := CASE WHEN NEW.planned_start_local IS NULL THEN NULL
                                ELSE (NEW.planned_local_date + NEW.planned_start_local) AT TIME ZONE NEW.timezone_name END;
  RETURN NEW;
END; $body$;
CREATE TRIGGER plan_items_guard
  BEFORE INSERT OR UPDATE OR DELETE ON plan_items
  FOR EACH ROW EXECUTE FUNCTION guard_plan_item();

-- ======================================================================================================
-- 3. Status transitions — append-only, one row per change, with actor, time and reason
-- ======================================================================================================
CREATE TABLE plan_item_status_events (
  event_id            uuid PRIMARY KEY,
  plan_item_id        uuid NOT NULL,
  student_id          uuid NOT NULL,
  seq_no              integer NOT NULL CHECK (seq_no > 0),
  from_status         text NOT NULL CHECK (from_status IN ('planned','in_progress','completed','partially_completed','deferred','skipped','cancelled')),
  to_status           text NOT NULL CHECK (to_status   IN ('planned','in_progress','completed','partially_completed','deferred','skipped','cancelled')),
  deferral_reason     text CHECK (deferral_reason IN ('insufficient_time','schedule_conflict','prerequisite_not_mastered',
                        'difficulty','illness_or_absence','resource_unavailable','higher_priority_task',
                        'student_requested','counselor_adjustment','other')),
  reason_note         text,
  actor_kind          text NOT NULL CHECK (actor_kind IN ('membership','student')),
  actor_membership_id uuid REFERENCES workspace_memberships(membership_id),
  occurred_at         timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (plan_item_id, student_id) REFERENCES plan_items(plan_item_id, student_id),
  -- Concurrent transitions from the same state compute the same seq_no; this makes the second one fail
  -- instead of forking the history.
  UNIQUE (plan_item_id, seq_no),
  CHECK (to_status <> from_status),
  -- decision: `deferred` requires a reason, and only `deferred` carries one
  CHECK ((to_status = 'deferred') = (deferral_reason IS NOT NULL)),
  -- decision: every transition is auditable with a reason. For `deferred` the reason code is the reason
  -- and the note is optional ("other may carry an explanatory note"); for every other transition the
  -- reason is the note, so it is required.
  CHECK (to_status = 'deferred' OR length(btrim(coalesce(reason_note,''))) > 0),
  CHECK ((actor_kind = 'membership') = (actor_membership_id IS NOT NULL))
);

CREATE FUNCTION plan_item_current_status_of(p_item uuid) RETURNS text
LANGUAGE sql STABLE AS $body$
  SELECT coalesce((SELECT e.to_status FROM public.plan_item_status_events e
                    WHERE e.plan_item_id = p_item ORDER BY e.seq_no DESC LIMIT 1), 'planned');
$body$;

-- H-04: the accepted PO decisions authorize actor categories and terminal states, but do NOT define
-- the complete from_status -> to_status graph. Keep this table EMPTY in the base draft. A later, explicit
-- Product Owner decision must populate it through a reviewed migration; absent an exact edge, the guard
-- refuses the transition. Test-only fixtures may populate it in disposable synthetic databases.
CREATE TABLE plan_item_transition_rules (
  actor_kind  text NOT NULL CHECK (actor_kind IN ('membership','student')),
  from_status text NOT NULL CHECK (from_status IN ('planned','in_progress','completed','partially_completed','deferred','skipped','cancelled')),
  to_status   text NOT NULL CHECK (to_status IN ('planned','in_progress','completed','partially_completed','deferred','skipped','cancelled')),
  PRIMARY KEY (actor_kind, from_status, to_status),
  CHECK (from_status <> to_status)
);
REVOKE ALL ON TABLE plan_item_transition_rules FROM PUBLIC;

CREATE FUNCTION guard_plan_item_status_event() RETURNS trigger LANGUAGE plpgsql AS $body$
DECLARE v_current text; v_next integer;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RAISE EXCEPTION 'plan item status history is append-only' USING ERRCODE='check_violation';
  END IF;
  -- F-01 / F-05: only the NOLOGIN synthetic writer may write transitions at all; no runtime write path.
  IF NOT public.plan_identity_is('synthetic_plan_writer') THEN
    RAISE EXCEPTION 'no application identity can be authenticated as a plan actor until the WS-ISO-01 caller '
                    'binding exists; transitions are writable only by the synthetic test identity'
      USING ERRCODE='insufficient_privilege';
  END IF;
  -- WS-ISO-01 (decision B): the actor named on the row must BE the verified principal of this transaction.
  -- A student actor is the student who owns the item; a membership actor is that counselor membership.
  IF NEW.actor_kind = 'student' THEN
    IF public.current_principal_student() IS NULL OR public.current_principal_student() IS DISTINCT FROM NEW.student_id THEN
      RAISE EXCEPTION 'a student transition must be made by that student as the verified principal'
        USING ERRCODE='insufficient_privilege';
    END IF;
  ELSE
    IF public.current_principal_membership() IS NULL
       OR NEW.actor_membership_id IS DISTINCT FROM public.current_principal_membership() THEN
      RAISE EXCEPTION 'the transition actor must be the verified principal of this transaction'
        USING ERRCODE='insufficient_privilege';
    END IF;
  END IF;
  -- Decision B1 (Product Owner, 2026-11-20): no status transition on the items of a draft version.
  IF (SELECT v.status FROM public.plan_items i JOIN public.student_plan_versions v
        ON v.plan_version_id = i.plan_version_id WHERE i.plan_item_id = NEW.plan_item_id) IS DISTINCT FROM 'published' THEN
    RAISE EXCEPTION 'status transitions on items of a DRAFT plan version are prohibited (Product Owner '
                    'decision WS-PLAN-01 B1)' USING ERRCODE='check_violation';
  END IF;
  SELECT coalesce(max(e.seq_no), 0) + 1 INTO v_next
    FROM public.plan_item_status_events e WHERE e.plan_item_id = NEW.plan_item_id;
  IF NEW.seq_no <> v_next THEN
    RAISE EXCEPTION 'transition % of plan item % is out of order: the next one is %',
      NEW.seq_no, NEW.plan_item_id, v_next USING ERRCODE='check_violation';
  END IF;
  v_current := public.plan_item_current_status_of(NEW.plan_item_id);
  IF NEW.from_status <> v_current THEN
    -- A stale transition: the caller believed the item was in another state. Refused rather than applied,
    -- so a history can never read planned -> completed while the item had already been cancelled.
    RAISE EXCEPTION 'plan item % is %, not %; refusing a stale transition',
      NEW.plan_item_id, v_current, NEW.from_status USING ERRCODE='check_violation';
  END IF;
  -- Decision D1: completed, skipped and cancelled are terminal and cannot be reversed. A correction is a
  -- new plan version.
  IF v_current IN ('completed','skipped','cancelled') THEN
    RAISE EXCEPTION 'plan item % is %, a terminal status; correct it through a new plan version (decision D1)',
      NEW.plan_item_id, v_current USING ERRCODE='check_violation';
  END IF;
  -- Decision A2: students may record in_progress, completed, partially_completed; only the responsible
  -- counselor may record deferred, skipped, cancelled. Everything these decisions do not name is refused
  -- and recorded as open: a counselor recording a student status, a student recording a counselor status,
  -- and any transition TO planned (no actor is named for it).
  IF NEW.to_status = 'planned' THEN
    RAISE EXCEPTION 'no actor is authorized to record a transition to planned; undecided, refused (WS-PLAN-01 open)'
      USING ERRCODE='insufficient_privilege';
  END IF;
  IF NEW.actor_kind = 'student' THEN
    IF NEW.to_status NOT IN ('in_progress','completed','partially_completed') THEN
      RAISE EXCEPTION 'a student may record only in_progress, completed or partially_completed (decision A2)'
        USING ERRCODE='insufficient_privilege';
    END IF;
  ELSE
    IF NEW.to_status NOT IN ('deferred','skipped','cancelled') THEN
      RAISE EXCEPTION 'whether a counselor may record % is undecided; refused (decision A2 names students for it)',
        NEW.to_status USING ERRCODE='insufficient_privilege';
    END IF;
    IF NOT public.counselor_is_responsible_for(NEW.actor_membership_id, NEW.student_id) THEN
      RAISE EXCEPTION 'membership % is not the responsible counselor of student %',
        NEW.actor_membership_id, NEW.student_id USING ERRCODE='insufficient_privilege';
    END IF;
  END IF;
  -- H-04: actor/destination authorization is not a substitute for an approved state edge. This table is
  -- empty in the schema draft; therefore every edge remains refused until the Product Owner approves it.
  IF NOT EXISTS (
    SELECT 1 FROM public.plan_item_transition_rules r
     WHERE r.actor_kind = NEW.actor_kind
       AND r.from_status = NEW.from_status
       AND r.to_status = NEW.to_status
  ) THEN
    RAISE EXCEPTION 'transition edge % -> % for actor % is not explicitly approved; refused fail-closed (WS-PLAN-01 open)',
      NEW.from_status, NEW.to_status, NEW.actor_kind USING ERRCODE='insufficient_privilege';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER plan_item_status_events_guard
  BEFORE INSERT OR UPDATE OR DELETE ON plan_item_status_events
  FOR EACH ROW EXECUTE FUNCTION guard_plan_item_status_event();

CREATE VIEW plan_item_current_status AS
  SELECT i.plan_item_id, i.plan_version_id, i.student_id,
         coalesce(e.to_status, 'planned') AS status,
         e.deferral_reason, e.reason_note, e.occurred_at AS status_changed_at
    FROM public.plan_items i
    LEFT JOIN LATERAL (SELECT * FROM public.plan_item_status_events x
                        WHERE x.plan_item_id = i.plan_item_id ORDER BY x.seq_no DESC LIMIT 1) e ON true;

-- ======================================================================================================
-- 4. Output JSON is DERIVED from the items, never stored beside them
-- ======================================================================================================
CREATE VIEW plan_version_rendered AS
  SELECT v.plan_version_id, v.plan_id, v.version_no, v.status AS version_status,
         CASE WHEN v.content_model = 'legacy_json' THEN v.plan_content
              ELSE jsonb_build_object(
                'plan_version_id', v.plan_version_id,
                'version_no', v.version_no,
                'items', coalesce((
                  SELECT jsonb_agg(jsonb_build_object(
                           'item_no', i.item_no,
                           'source', CASE WHEN i.topic_id      IS NOT NULL THEN 'topic'
                                          WHEN i.subtopic_id   IS NOT NULL THEN 'subtopic'
                                          WHEN i.activity_id   IS NOT NULL THEN 'activity'
                                          WHEN i.exam_id       IS NOT NULL THEN 'exam'
                                          WHEN i.review_id     IS NOT NULL THEN 'review'
                                          ELSE 'assignment' END,
                           'source_id', coalesce(i.topic_id, i.subtopic_id, i.activity_id, i.exam_id,
                                                 i.review_id, i.assignment_id),
                           'planned_local_date', i.planned_local_date,
                           'planned_start_local', i.planned_start_local,
                           'planned_minutes', i.planned_minutes,
                           'timezone', i.timezone_name,
                           'status', s.status,
                           'deferral_reason', s.deferral_reason) ORDER BY i.item_no)
                    FROM public.plan_items i
                    JOIN public.plan_item_current_status s ON s.plan_item_id = i.plan_item_id
                   WHERE i.plan_version_id = v.plan_version_id), '[]'::jsonb))
         END AS rendered,
         v.content_model
    FROM public.student_plan_versions v;

-- ======================================================================================================
-- 5. The transfer barrier and TRUNCATE
-- ======================================================================================================
-- The barrier is installed by a catalog-driven loop in workspace_transfer_freeze.sql, which ran before
-- these tables existed, so it is attached here with the same function. FRZ-style coverage is asserted by
-- PLN-C1 rather than assumed.
DO $install$
DECLARE r record; n integer := 0;
BEGIN
  FOR r IN SELECT table_name, key_column, key_kind FROM public.student_scoped_tables
            WHERE table_name IN ('plan_items','plan_item_status_events') ORDER BY table_name
  LOOP
    -- Same trigger NAME as the freeze file's loop, so student_write_barrier_coverage sees it.
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON public.%I
         FOR EACH ROW EXECUTE FUNCTION public.student_write_barrier(%L, %L)',
      'zz_transfer_write_barrier_' || r.table_name, r.table_name, r.key_column, r.key_kind);
    n := n + 1;
  END LOOP;
  IF n <> 2 THEN
    RAISE EXCEPTION 'expected student_scoped_tables to list both plan tables, found %', n;
  END IF;
END
$install$;

CREATE FUNCTION reject_plan_truncate() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION '% is append-only; TRUNCATE is refused', TG_TABLE_NAME USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER plan_items_no_truncate BEFORE TRUNCATE ON plan_items
  FOR EACH STATEMENT EXECUTE FUNCTION reject_plan_truncate();
CREATE TRIGGER plan_item_status_events_no_truncate BEFORE TRUNCATE ON plan_item_status_events
  FOR EACH STATEMENT EXECUTE FUNCTION reject_plan_truncate();

COMMIT;
