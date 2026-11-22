-- WS-ISO-01 decision B — signed principal assertions (TEST-ONLY key) and row-level security bound to the
-- verified principal. SYNTHETIC ONLY (D-014).
-- Runs AFTER workspace_counselor_isolation_tests.sql in the same database (it reuses that suite's fixtures:
-- counselor A owns a1 (and a2, whose assignment that suite ENDS), counselor B owns b1, C is co-assigned to a1
-- and not responsible, E is suspended). Run with -v workspace_key.
--
-- THE TEST KEY. Derived below from a public string. It is not a secret, protects nothing, and appears in no
-- draft file. The key table cannot hold any other kind of key (ISO-P01).
--
-- Every identity below is a real PostgreSQL role. The runtime acts through its LOGIN identity
-- (SET SESSION AUTHORIZATION, which is how a pooled application connection presents itself) and presents an
-- assertion to establish_principal(); nothing is simulated with a variable or a flag.
\set ON_ERROR_STOP on
SET app.workspace_key = :'workspace_key';
SELECT format('ws_%s_runtime', :'workspace_key')        AS runtime_role \gset
SELECT format('ws_%s_runtime_login', :'workspace_key')  AS runtime_login \gset
SELECT format('ws_%s_worker_login', :'workspace_key')   AS worker_login \gset
SELECT format('ws_%s_exporter_login', :'workspace_key') AS exporter_login \gset
\set WS     'a5000000-0000-0000-0000-000000000001'
\set MA     'b5000000-0000-0000-0000-00000000000a'
\set MB     'b5000000-0000-0000-0000-00000000000b'
\set MC     'b5000000-0000-0000-0000-00000000000c'
\set ME     'b5000000-0000-0000-0000-00000000000e'
\set SA1    'e5000000-0000-0000-0000-0000000000a1'
\set SB1    'e5000000-0000-0000-0000-0000000000b1'

CREATE OR REPLACE FUNCTION p_err(label text, stmt text, want_state text, want_msg text) RETURNS void
LANGUAGE plpgsql AS $t$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN others THEN
    IF SQLSTATE <> want_state OR position(want_msg IN SQLERRM) = 0 THEN
      RAISE EXCEPTION 'FAIL %: expected % "%", got % "%"', label, want_state, want_msg, SQLSTATE, SQLERRM;
    END IF;
    RAISE NOTICE 'PASS % (SQLSTATE %, reason verified)', label, SQLSTATE;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL %: statement unexpectedly succeeded', label;
END; $t$;
CREATE OR REPLACE FUNCTION p_ok(label text, stmt text) RETURNS void LANGUAGE plpgsql AS $t$
BEGIN
  EXECUTE stmt;
  RAISE NOTICE 'PASS % (accepted)', label;
END; $t$;

-- Builds an assertion line and signs it. Superuser-only scaffolding: it needs the key, which no
-- application role can read.
CREATE OR REPLACE FUNCTION p_mk(p_kind text, p_actor uuid, p_iat_off integer DEFAULT -5, p_life integer DEFAULT 120,
                                p_ws uuid DEFAULT 'a5000000-0000-0000-0000-000000000001',
                                p_key_id text DEFAULT 'synthetic-test-iso-01', p_key bytea DEFAULT NULL,
                                p_nonce text DEFAULT NULL)
RETURNS TABLE (a text, s text) LANGUAGE plpgsql AS $t$
DECLARE v_iat bigint := extract(epoch FROM clock_timestamp())::bigint + p_iat_off; v_line text; v_key bytea;
BEGIN
  v_key := coalesce(p_key, (SELECT k.key_material FROM principal_assertion_keys k WHERE k.key_id = p_key_id));
  v_line := format('wsp1;%s;%s;%s;%s;%s;%s;%s', p_ws, p_kind, p_actor, v_iat, v_iat + p_life,
                   coalesce(p_nonce, encode(ext_crypto.gen_random_bytes(16), 'hex')), p_key_id);
  RETURN QUERY SELECT v_line, encode(ext_crypto.hmac(convert_to(v_line,'UTF8'), v_key, 'sha256'), 'hex');
END; $t$;

-- ======================================================================================================
-- The key, and production fail-closed
-- ======================================================================================================
INSERT INTO principal_assertion_keys(key_id, algorithm, key_material, max_lifetime)
VALUES ('synthetic-test-iso-01', 'hmac-sha256-synthetic-test',
        ext_crypto.digest('WS-ISO-01 synthetic test key - public, not a secret, never for production', 'sha256'),
        interval '5 minutes');
SELECT p_err('ISO-P01a the key table cannot hold a key that is not a synthetic test key',
  $q$INSERT INTO principal_assertion_keys(key_id,algorithm,key_material,max_lifetime)
     VALUES ('production-key-1','hmac-sha256-synthetic-test',ext_crypto.digest('x','sha256'),interval '1 minute')$q$,
  '23514', 'principal_assertion_keys_key_id_check');
SELECT p_err('ISO-P01b ... nor any algorithm but the test-only HMAC',
  $q$INSERT INTO principal_assertion_keys(key_id,algorithm,key_material,max_lifetime)
     VALUES ('synthetic-test-other','ed25519',ext_crypto.digest('x','sha256'),interval '1 minute')$q$,
  '23514', 'principal_assertion_keys_algorithm_check');
SELECT iso_true('ISO-P00a verification mode is DISABLED by default (production fail-closed)',
  (SELECT mode FROM principal_verification_config) = 'disabled');
SELECT a, s FROM p_mk('counselor', :'MA') \gset A0_
SET SESSION AUTHORIZATION :"runtime_login";
SELECT p_err('ISO-P00b with verification disabled, even a correctly signed assertion is refused',
  format('SELECT establish_principal(%L,%L)', :'A0_a', :'A0_s'), '42501', 'production verification is fail-closed');
SELECT p_err('ISO-P02a the runtime cannot read the key', 'SELECT * FROM principal_assertion_keys', '42501', 'permission denied');
SELECT p_err('ISO-P02b the runtime cannot switch verification on', $q$UPDATE principal_verification_config SET mode='synthetic_test'$q$, '42501', 'permission denied');
SELECT p_err('ISO-P02c the runtime cannot write a "verified" principal row itself',
  format($q$INSERT INTO verified_principal_context(backend_pid,xact_id,session_role,actor_kind,membership_id,nonce,verified_at)
            VALUES (pg_backend_pid(),pg_current_xact_id(),session_user,'counselor',%L,'00000000000000000000000000000000',clock_timestamp())$q$, :'MA'),
  '42501', 'permission denied');
SELECT p_err('ISO-P02d the runtime cannot reach the HMAC primitive', $q$SELECT ext_crypto.hmac('a'::bytea,'b'::bytea,'sha256')$q$, '42501', 'permission denied for schema ext_crypto');
SELECT p_err('ISO-P02e the runtime cannot read the nonce ledger', 'SELECT * FROM principal_assertion_nonces', '42501', 'permission denied');
RESET SESSION AUTHORIZATION;

-- The synthetic test harness, and only it, enables verification.
UPDATE principal_verification_config SET mode = 'synthetic_test';

-- ======================================================================================================
-- ISO-GAP-01..03, now as hard assertions under each counselor's OWN verified identity
-- ======================================================================================================
SELECT a, s FROM p_mk('counselor', :'MA') \gset A_
SELECT a, s FROM p_mk('counselor', :'MB') \gset SW_
SET SESSION AUTHORIZATION :"runtime_login";
BEGIN;
SELECT p_ok('ISO-P10 counselor A establishes a verified principal from a correctly signed assertion',
  format('SELECT establish_principal(%L,%L)', :'A_a', :'A_s'));
SELECT iso_true('ISO-P10b the verified principal is A', current_principal_membership() = :'MA');
SELECT iso_true('ISO-RLS-01 (was ISO-GAP-01) A does NOT read B''s study session directly',
  NOT EXISTS (SELECT 1 FROM study_sessions WHERE study_session_id = 'a5300000-0000-0000-0000-0000000000b1'));
SELECT iso_true('ISO-RLS-01b ... and DOES read own student a1''s session (30 minutes)',
  (SELECT actual_minutes FROM study_sessions WHERE study_session_id = 'a5300000-0000-0000-0000-0000000000a1') = 30);
SELECT iso_true('ISO-RLS-01c ... and not a2''s, whose assignment was ended (live revocation)',
  NOT EXISTS (SELECT 1 FROM study_sessions WHERE study_session_id = 'a5300000-0000-0000-0000-0000000000a2'));
SELECT iso_true('ISO-RLS-02 (was ISO-GAP-02) A reads own private note, and not B''s',
  (SELECT array_agg(counselor_note_id ORDER BY counselor_note_id::text) FROM counselor_notes WHERE visibility='private_to_author')
   = ARRAY['a5800000-0000-0000-0000-0000000000a1'::uuid]);
SELECT iso_true('ISO-RLS-04a by changing the object id: B''s file, notification, plan version and student are all invisible',
  NOT EXISTS (SELECT 1 FROM private_file_objects  WHERE file_id='a5400000-0000-0000-0000-0000000000b1')
  AND NOT EXISTS (SELECT 1 FROM in_app_notifications WHERE notification_id='a5500000-0000-0000-0000-0000000000b1')
  AND NOT EXISTS (SELECT 1 FROM student_plan_versions WHERE plan_version_id='a5610000-0000-0000-0000-0000000000b1')
  AND NOT EXISTS (SELECT 1 FROM students WHERE student_id=:'SB1'));
SELECT iso_false('ISO-RLS-04b by supplying B''s membership id to the row function: still nothing',
  counselor_may_access_row(:'MB','study_sessions','a5300000-0000-0000-0000-0000000000b1'));
SELECT iso_true('ISO-RLS-04c ... nor B''s caseload list or report',
  NOT EXISTS (SELECT 1 FROM counselor_visible_students(:'MB'))
  AND NOT EXISTS (SELECT 1 FROM counselor_caseload_report(:'MB')));
SELECT iso_true('ISO-RLS-05 A''s own report totals exactly 30 minutes (a1 only)',
  (SELECT sum(study_minutes) FROM counselor_caseload_report(:'MA')) = 30);
SELECT p_err('ISO-RLS-06a A cannot WRITE a study session for B''s student',
  format($q$INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES (gen_random_uuid(),%L,clock_timestamp(),1)$q$, :'SB1'),
  '42501', 'row-level security');
DO $u$
DECLARE n integer;
BEGIN
  UPDATE study_sessions SET actual_minutes = 0 WHERE study_session_id='a5300000-0000-0000-0000-0000000000b1';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL ISO-RLS-06b an UPDATE reached B''s row (% rows)', n; END IF;
  RAISE NOTICE 'PASS ISO-RLS-06b an UPDATE of B''s row touches nothing (the row is invisible)';
END $u$;
SELECT p_err('ISO-RLS-06c A cannot write a note in C''s name, even about A''s own student (impersonation)',
  format($q$INSERT INTO counselor_notes(counselor_note_id,student_id,author_membership_id,visibility,content) VALUES (gen_random_uuid(),%L,%L,'workspace_scoped','x')$q$, :'SA1', :'MC'),
  '42501', 'row-level security');
SELECT p_ok('ISO-RLS-06d A CAN write a note in A''s own name about A''s own student',
  format($q$INSERT INTO counselor_notes(counselor_note_id,student_id,author_membership_id,visibility,content) VALUES (gen_random_uuid(),%L,%L,'workspace_scoped','synthetic')$q$, :'SA1', :'MA'));
-- (Plan-version authorship under a verified principal is tested in the plan suite, where the author column exists: PLN-P*.)
SELECT p_err('ISO-P28 a second assertion in the same transaction cannot switch the identity',
  format('SELECT establish_principal(%L,%L)', :'SW_a', :'SW_s'), '42501', 'already established');
COMMIT;
RESET SESSION AUTHORIZATION;

SELECT iso_true('ISO-RLS-03 (was ISO-GAP-03) row-level security is ENABLED and FORCED on every student-scoped table, each with the policy',
  (SELECT bool_and(c.relrowsecurity AND c.relforcerowsecurity
                   AND EXISTS (SELECT 1 FROM pg_policy p WHERE p.polrelid = c.oid AND p.polname = 'iso_counselor_scope'))
     FROM student_scoped_tables t JOIN pg_class c ON c.oid = ('public.'||t.table_name)::regclass)
  AND (SELECT count(*) FROM student_scoped_tables) = 32);

-- Co-assigned counselor C: reaches a1 but not A's private note
SELECT a, s FROM p_mk('counselor', :'MC') \gset C_
SET SESSION AUTHORIZATION :"runtime_login";
BEGIN;
SELECT establish_principal(:'C_a', :'C_s');
SELECT iso_true('ISO-RLS-02b co-assigned C sees A''s workspace-scoped note on a1 but NOT A''s private note',
  EXISTS (SELECT 1 FROM counselor_notes WHERE counselor_note_id='a5800000-0000-0000-0000-0000000000a2')
  AND NOT EXISTS (SELECT 1 FROM counselor_notes WHERE counselor_note_id='a5800000-0000-0000-0000-0000000000a1'));
COMMIT;
RESET SESSION AUTHORIZATION;

-- B sees B's own and nothing of A's
SELECT a, s FROM p_mk('counselor', :'MB') \gset B_
SET SESSION AUTHORIZATION :"runtime_login";
BEGIN;
SELECT establish_principal(:'B_a', :'B_s');
SELECT iso_true('ISO-RLS-01d B reads B''s session (999) and nothing of A''s',
  (SELECT array_agg(actual_minutes) FROM study_sessions) = ARRAY[999]);
COMMIT;
RESET SESSION AUTHORIZATION;

-- ======================================================================================================
-- Missing identity, pooled-session leak, other application roles
-- ======================================================================================================
SET SESSION AUTHORIZATION :"runtime_login";
SELECT iso_true('ISO-RLS-07 with NO principal the runtime sees no student, session, note or file',
  NOT EXISTS (SELECT 1 FROM students) AND NOT EXISTS (SELECT 1 FROM study_sessions)
  AND NOT EXISTS (SELECT 1 FROM counselor_notes) AND NOT EXISTS (SELECT 1 FROM private_file_objects));
SELECT p_err('ISO-RLS-07b with NO principal the runtime cannot write',
  format($q$INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES (gen_random_uuid(),%L,clock_timestamp(),1)$q$, :'SA1'),
  '42501', 'row-level security');
RESET SESSION AUTHORIZATION;
SELECT a, s FROM p_mk('counselor', :'MA') \gset A2_
BEGIN;
SET SESSION AUTHORIZATION :"runtime_login";
SELECT establish_principal(:'A2_a', :'A2_s');
SELECT iso_true('ISO-RLS-08a (pool) inside the establishing transaction the principal is A', current_principal_membership() = :'MA');
COMMIT;
SELECT iso_true('ISO-RLS-08b (pool) the NEXT transaction on the same session has NO principal and sees nothing',
  current_principal_membership() IS NULL AND NOT EXISTS (SELECT 1 FROM study_sessions));
RESET SESSION AUTHORIZATION;
SELECT a, s FROM p_mk('counselor', :'MA') \gset A3_
SET SESSION AUTHORIZATION :"runtime_login";
BEGIN;
SELECT establish_principal(:'A3_a', :'A3_s');
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"worker_login";
SELECT iso_true('ISO-RLS-08c the principal is bound to the session role that established it: another role on the same backend gets none',
  current_principal_membership() IS NULL);
ROLLBACK;
RESET SESSION AUTHORIZATION;
SET SESSION AUTHORIZATION :"worker_login";
-- The worker's only student-scoped privilege is SELECT/UPDATE on in_app_notifications (delivery). Without a
-- verified principal it reaches none of them: background-job identity is undecided, so it fails closed.
SELECT iso_true('ISO-RLS-09a the worker, with no principal, reads no notification (job context undecided: fail-closed)',
  NOT EXISTS (SELECT 1 FROM in_app_notifications));
DO $u$
DECLARE n integer;
BEGIN
  UPDATE in_app_notifications SET read_at = clock_timestamp();
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL ISO-RLS-09c the worker updated % notifications without a principal', n; END IF;
  RAISE NOTICE 'PASS ISO-RLS-09c the worker, with no principal, updates no notification';
END $u$;
SELECT p_err('ISO-RLS-09b the worker cannot establish a principal (no EXECUTE)',
  format('SELECT establish_principal(%L,%L)', :'A0_a', :'A0_s'), '42501', 'permission denied for function establish_principal');
RESET SESSION AUTHORIZATION;

-- ======================================================================================================
-- Forged, tampered, expired, replayed, cross-tenant, cross-actor, stale
-- ======================================================================================================
SELECT a, s FROM p_mk('counselor', :'MA') \gset T_
SELECT replace(:'T_a', :'MA', :'MB') AS t_tampered \gset
SELECT a AS f_a, s AS f_s FROM p_mk('counselor', :'MA', p_key => ext_crypto.digest('an attacker''s key','sha256')) \gset
SELECT a, s FROM p_mk('counselor', :'MA', -600, 120) \gset EXP_
SELECT a, s FROM p_mk('counselor', :'MA', 300, 120) \gset FUT_
SELECT a, s FROM p_mk('counselor', :'MA', -5, 3600) \gset LONG_
SELECT a, s FROM p_mk('counselor', :'MA', p_ws => 'a9999999-0000-0000-0000-000000000001') \gset XWS_
SELECT a, s FROM p_mk('counselor', :'SA1') \gset XACT_
SELECT a, s FROM p_mk('student',   :'MA') \gset XACT2_
SELECT a, s FROM p_mk('counselor', :'ME') \gset STALE_
SELECT a, s FROM p_mk('counselor', :'MA') \gset REP_
SET SESSION AUTHORIZATION :"runtime_login";
SELECT p_err('ISO-P20 TAMPERED: the actor changed from A to B under A''s signature',
  format('SELECT establish_principal(%L,%L)', :'t_tampered', :'T_s'), '42501', 'signature is invalid');
SELECT p_err('ISO-P20b TAMPERED: one hex digit of the signature changed',
  format('SELECT establish_principal(%L,%L)', :'T_a', overlay(:'T_s' placing CASE WHEN substr(:'T_s',1,1)='0' THEN '1' ELSE '0' END from 1 for 1)),
  '42501', 'signature is invalid');
SELECT p_err('ISO-P21 FORGED: signed with a key the database does not hold',
  format('SELECT establish_principal(%L,%L)', :'f_a', :'f_s'), '42501', 'signature is invalid');
SELECT p_err('ISO-P22a EXPIRED', format('SELECT establish_principal(%L,%L)', :'EXP_a', :'EXP_s'), '42501', 'has expired');
SELECT p_err('ISO-P22b NOT YET VALID', format('SELECT establish_principal(%L,%L)', :'FUT_a', :'FUT_s'), '42501', 'not yet valid');
SELECT p_err('ISO-P22c LIFETIME longer than the key allows', format('SELECT establish_principal(%L,%L)', :'LONG_a', :'LONG_s'), '42501', 'lifetime exceeds');
SELECT p_err('ISO-P24 CROSS-TENANT: a valid assertion for another Workspace',
  format('SELECT establish_principal(%L,%L)', :'XWS_a', :'XWS_s'), '42501', 'another Workspace');
SELECT p_err('ISO-P25a CROSS-ACTOR: a student''s id presented as a counselor',
  format('SELECT establish_principal(%L,%L)', :'XACT_a', :'XACT_s'), '42501', 'not an active counselor membership');
SELECT p_err('ISO-P25b CROSS-ACTOR: a counselor''s id presented as a student',
  format('SELECT establish_principal(%L,%L)', :'XACT2_a', :'XACT2_s'), '42501', 'not an active student');
SELECT p_err('ISO-P27 STALE IDENTITY: a validly signed assertion for a SUSPENDED membership',
  format('SELECT establish_principal(%L,%L)', :'STALE_a', :'STALE_s'), '42501', 'not an active counselor membership');
SELECT p_err('ISO-P29a MALFORMED: an extra field', format('SELECT establish_principal(%L,%L)', :'T_a'||';x', :'T_s'), '42501', 'malformed');
SELECT p_err('ISO-P29b MALFORMED: an upper-case signature', format('SELECT establish_principal(%L,%L)', :'T_a', upper(:'T_s')), '42501', 'malformed');
BEGIN;
SELECT p_ok('ISO-P23a the assertion is accepted once', format('SELECT establish_principal(%L,%L)', :'REP_a', :'REP_s'));
COMMIT;
SELECT p_err('ISO-P23b REPLAY: the same assertion, in a new transaction, is refused (idempotent: no new principal)',
  format('SELECT establish_principal(%L,%L)', :'REP_a', :'REP_s'), '42501', 'replayed');
SELECT iso_true('ISO-P23c ... and the refused replay left no principal behind', current_principal_membership() IS NULL);
RESET SESSION AUTHORIZATION;

-- Stale ASSIGNMENT: identity is still valid, but access is decided live, row by row
SELECT a, s FROM p_mk('counselor', :'MA') \gset LIVE_
SET SESSION AUTHORIZATION :"runtime_login";
BEGIN;
SELECT establish_principal(:'LIVE_a', :'LIVE_s');
SELECT iso_true('ISO-P27b before revocation A sees a1', EXISTS (SELECT 1 FROM students WHERE student_id = :'SA1'));
RESET SESSION AUTHORIZATION;
UPDATE counselor_assignments SET state='ended', ended_at=clock_timestamp() WHERE assignment_id='a5200000-0000-0000-0000-0000000000a1';
SET SESSION AUTHORIZATION :"runtime_login";
SELECT iso_true('ISO-P27c after the assignment ends, in the SAME transaction, a1 is gone',
  NOT EXISTS (SELECT 1 FROM students WHERE student_id = :'SA1'));
ROLLBACK;
RESET SESSION AUTHORIZATION;

-- Key revocation
UPDATE principal_assertion_keys SET revoked_at = clock_timestamp() WHERE key_id = 'synthetic-test-iso-01';
SELECT a, s FROM p_mk('counselor', :'MA') \gset REV_
SET SESSION AUTHORIZATION :"runtime_login";
SELECT p_err('ISO-P30 a REVOKED key verifies nothing', format('SELECT establish_principal(%L,%L)', :'REV_a', :'REV_s'), '42501', 'revoked');
RESET SESSION AUTHORIZATION;
UPDATE principal_assertion_keys SET revoked_at = NULL WHERE key_id = 'synthetic-test-iso-01';

-- A student principal reads nothing directly: what a student may read is not decided (fail-closed)
SELECT a, s FROM p_mk('student', :'SA1') \gset STU_
SET SESSION AUTHORIZATION :"runtime_login";
BEGIN;
SELECT establish_principal(:'STU_a', :'STU_s');
SELECT iso_true('ISO-P26 a verified STUDENT principal is recorded as that student and reads no row directly (undecided)',
  current_principal_student() = :'SA1' AND current_principal_membership() IS NULL
  AND NOT EXISTS (SELECT 1 FROM students) AND NOT EXISTS (SELECT 1 FROM study_sessions));
COMMIT;
RESET SESSION AUTHORIZATION;

-- Every role that holds a privilege on a student-scoped table is classified: filtered application role,
-- or a reviewed NOLOGIN owner / synthetic test identity outside RLS. An unclassified role fails.
-- Effective-privilege audit: covers direct and inherited role grants, table-level and column-level
-- privileges, and PUBLIC (which has no pg_roles row but is reflected by has_*_privilege).
SELECT iso_true('ISO-RLS-C3 every effective holder of a student-scoped table/column privilege is classified',
  NOT EXISTS (
    SELECT 1
      FROM pg_catalog.pg_roles r
     WHERE EXISTS (
       SELECT 1
         FROM public.student_scoped_tables t
         JOIN pg_catalog.pg_class c ON c.relnamespace = 'public'::regnamespace AND c.relname = t.table_name
        WHERE has_table_privilege(r.oid, c.oid, 'SELECT')
           OR has_table_privilege(r.oid, c.oid, 'INSERT')
           OR has_table_privilege(r.oid, c.oid, 'UPDATE')
           OR has_table_privilege(r.oid, c.oid, 'DELETE')
           OR EXISTS (
             SELECT 1 FROM pg_catalog.pg_attribute a
              WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                AND (has_column_privilege(r.oid, c.oid, a.attname, 'SELECT')
                  OR has_column_privilege(r.oid, c.oid, a.attname, 'INSERT')
                  OR has_column_privilege(r.oid, c.oid, a.attname, 'UPDATE'))
           )
     )
       AND r.rolname NOT IN (SELECT role_name::text FROM public.iso_application_roles)
       AND r.rolname NOT IN (SELECT role_name::text FROM public.iso_rls_bypass_roles)
       AND r.rolname <> current_user
  ));

SELECT iso_true('ISO-RLS-C10 bypass allowlist contains exactly the reviewed owner and synthetic identities',
  (SELECT array_agg(role_name ORDER BY role_name) FROM public.iso_rls_bypass_roles)
   = ARRAY[
     ('ws_'||:'workspace_key'||'_function_owner')::name,
     ('ws_'||:'workspace_key'||'_freeze_owner')::name,
     ('ws_'||:'workspace_key'||'_governance_owner')::name,
     ('ws_'||:'workspace_key'||'_inbox_owner')::name,
     ('ws_'||:'workspace_key'||'_plan_migrator')::name,
     ('ws_'||:'workspace_key'||'_synth_exec')::name,
     ('ws_'||:'workspace_key'||'_synth_inbox')::name,
     ('ws_'||:'workspace_key'||'_synth_plan_writer')::name,
     ('ws_'||:'workspace_key'||'_table_owner')::name
   ]::name[]);
SELECT iso_true('ISO-RLS-C11 every bypass identity is NOLOGIN, non-superuser, non-BYPASSRLS and membership-free',
  NOT EXISTS (
    SELECT 1 FROM public.iso_rls_bypass_roles b
    JOIN pg_catalog.pg_roles r ON r.rolname=b.role_name
    WHERE r.rolcanlogin OR r.rolsuper OR r.rolbypassrls OR
          EXISTS (SELECT 1 FROM pg_catalog.pg_auth_members m WHERE m.roleid=r.oid OR m.member=r.oid)
  ));

-- Unknown and indirect-grantee roles must not bypass the principal predicate merely because
-- they are absent from the application-role inventory. Exercise column grants, inherited grants and PUBLIC.
DO $roles$
DECLARE k text := current_setting('app.workspace_key');
BEGIN
  EXECUTE format('CREATE ROLE %I NOLOGIN INHERIT', 'ws_'||k||'_unclassified');
  EXECUTE format('CREATE ROLE %I NOLOGIN NOINHERIT', 'ws_'||k||'_unclassified_group');
  EXECUTE format('GRANT SELECT (student_id) ON TABLE students TO %I', 'ws_'||k||'_unclassified');
  EXECUTE format('GRANT SELECT ON TABLE students TO %I', 'ws_'||k||'_unclassified_group');
  EXECUTE format('GRANT %I TO %I', 'ws_'||k||'_unclassified_group', 'ws_'||k||'_unclassified');
END $roles$;

SELECT iso_true('ISO-RLS-C4 unknown column-grantee role is NOT exempt',
  NOT public.iso_rls_bypass(('ws_'||current_setting('app.workspace_key')||'_unclassified')::name));
-- An additional permissive policy must not OR-widen the mandatory restrictive tenant fence.
CREATE POLICY iso_test_widening_policy ON students AS PERMISSIVE FOR SELECT TO PUBLIC USING (true);
SELECT format('SET ROLE %I', 'ws_'||current_setting('app.workspace_key')||'_unclassified') \gexec
SELECT iso_true('ISO-RLS-C5 unknown role with only a column grant sees no student rows without a principal',
  NOT EXISTS (SELECT student_id FROM students));
RESET ROLE;
DROP POLICY iso_test_widening_policy ON students;

SELECT iso_true('ISO-RLS-C6 audit detects unclassified direct/column/inherited privilege holders',
  EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles r
     WHERE r.rolname = 'ws_'||current_setting('app.workspace_key')||'_unclassified'
       AND EXISTS (
         SELECT 1 FROM public.student_scoped_tables t
         JOIN pg_catalog.pg_class c ON c.relnamespace='public'::regnamespace AND c.relname=t.table_name
         WHERE has_table_privilege(r.oid,c.oid,'SELECT')
            OR EXISTS (SELECT 1 FROM pg_catalog.pg_attribute a
                        WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped
                          AND has_column_privilege(r.oid,c.oid,a.attname,'SELECT'))
       )
  ));

GRANT SELECT ON TABLE students TO PUBLIC;
SELECT iso_true('ISO-RLS-C7 audit detects PUBLIC table privileges as unclassified effective access',
  EXISTS (
    SELECT 1 FROM pg_catalog.pg_roles r
     WHERE r.rolname = 'ws_'||current_setting('app.workspace_key')||'_unclassified'
       AND has_table_privilege(r.oid,'public.students'::regclass,'SELECT')
       AND r.rolname NOT IN (SELECT role_name::text FROM public.iso_application_roles)
       AND r.rolname NOT IN (SELECT role_name::text FROM public.iso_rls_bypass_roles)
  ));
SELECT format('SET ROLE %I', 'ws_'||current_setting('app.workspace_key')||'_unclassified') \gexec
SELECT iso_true('ISO-RLS-C8 PUBLIC grant still cannot bypass verified-principal row filtering',
  NOT EXISTS (SELECT student_id FROM students));
RESET ROLE;
REVOKE SELECT ON TABLE students FROM PUBLIC;

DO $cleanup$
DECLARE k text := current_setting('app.workspace_key');
BEGIN
  EXECUTE format('REVOKE SELECT (student_id) ON TABLE students FROM %I', 'ws_'||k||'_unclassified');
  EXECUTE format('REVOKE SELECT ON TABLE students FROM %I', 'ws_'||k||'_unclassified_group');
  EXECUTE format('REVOKE %I FROM %I', 'ws_'||k||'_unclassified_group', 'ws_'||k||'_unclassified');
  EXECUTE format('DROP ROLE %I', 'ws_'||k||'_unclassified');
  EXECUTE format('DROP ROLE %I', 'ws_'||k||'_unclassified_group');
END $cleanup$;

UPDATE principal_verification_config SET mode = 'disabled';
SELECT 'PRINCIPAL ASSERTION TESTS COMPLETED (WS-ISO-01 decision B, test-only key; production verification fail-closed)' AS result;
