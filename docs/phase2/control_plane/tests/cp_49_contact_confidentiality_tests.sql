-- =============================================================================
-- CONTACT CONFIDENTIALITY AND KEY-MATERIAL ASSERTIONS (SYNTHETIC ONLY, D-014).
-- Run after the Control Plane schema and role files.
--
-- The Supervisor brief's Batch 7 asks for "no plaintext contact leakage" and "no secret or key material in
-- source code, logs, or Git". The first two are database properties and are asserted here from the
-- catalog, so a column or view added later fails the suite by name. The Git-history half is a repository
-- property and is checked by docs/phase2/tests/check_no_secret_material.py, which is a DOCUMENTATION /
-- REPOSITORY check and is reported separately from implementation evidence.
--
-- WHAT THESE DO NOT PROVE
--   Nothing about the strength of the cipher or the HMAC, which algorithms are used, or how keys are
--   provisioned, stored, rotated or revoked. Those are PS-1..PS-4 and deliberately undecided; this file
--   asserts only that no key material and no plaintext contact live in this database.
-- =============================================================================
\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------------------------------------
-- CID-01  No column anywhere may hold a plaintext contact. A contact column is permitted only as
--         ciphertext (bytea), a keyed fingerprint (bytea), a key version (integer) or an opaque
--         reference ending in _ref. A text column named like a phone number is the leak this forbids.
-- ---------------------------------------------------------------------------------------------------
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(c.relname || '.' || a.attname || ' ' || format_type(a.atttypid, a.atttypmod), ', '
                    ORDER BY c.relname, a.attname)
    INTO v_bad
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind IN ('r','v') AND a.attnum > 0 AND NOT a.attisdropped
     AND (a.attname ~* '(mobile|phone|msisdn|contact|e164)')
     AND format_type(a.atttypid, a.atttypmod) IN ('text','character varying','citext')
     AND a.attname !~* '(_ref|_kind|_key|_state|_status|_purpose|_reason|_version)$';
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CID-01 these text columns could hold a plaintext contact: %. A contact may exist '
                    'only as ciphertext, a keyed fingerprint, a key version or an opaque _ref.', v_bad;
  END IF;
  RAISE NOTICE 'PASS CID-01 no text column in this database can hold a plaintext contact';
END $t$;

-- ---------------------------------------------------------------------------------------------------
-- CID-02  The stored shapes are what they claim to be: the fingerprint is a fixed-width 32-byte digest
--         (so its length leaks nothing about the number) and the ciphertext is bytea.
-- ---------------------------------------------------------------------------------------------------
DO $t$
DECLARE v_missing text;
BEGIN
  SELECT string_agg(t.rel || '.' || t.col, ', ') INTO v_missing
    FROM (VALUES ('student_contact_index','mobile_hmac'),
                 ('enrollment_claim_identity_aliases','mobile_hmac'),
                 ('contact_change_proofs','new_contact_hmac')) AS t(rel,col)
   WHERE to_regclass('public.'||t.rel) IS NOT NULL
     AND NOT EXISTS (
       SELECT 1 FROM pg_constraint k
        WHERE k.conrelid = ('public.'||t.rel)::regclass AND k.contype = 'c'
          AND pg_get_constraintdef(k.oid) ~ ('octet_length\s*\(\s*' || t.col || '\s*\)\s*=\s*32'));
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CID-02 these fingerprints are not pinned to 32 bytes: %', v_missing;
  END IF;

  IF (SELECT format_type(a.atttypid, a.atttypmod) FROM pg_attribute a
       WHERE a.attrelid='public.student_contact_index'::regclass AND a.attname='mobile_ciphertext') <> 'bytea' THEN
    RAISE EXCEPTION 'FAIL CID-02 mobile_ciphertext is not bytea';
  END IF;
  RAISE NOTICE 'PASS CID-02 every contact fingerprint is a fixed 32-byte digest and the contact itself is bytea ciphertext';
END $t$;

-- ---------------------------------------------------------------------------------------------------
-- CID-03  THE KEY-VERSION TABLES HOLD NO KEY MATERIAL.
--
--         What they may hold: a version number, a state, timestamps, and an OPAQUE REFERENCE to an
--         external key manager. `mobile_encryption_key_versions.key_manager_ref` is exactly that — a
--         non-secret KMS/HSM key identifier — and it is the shape the register recommends for PS-3,
--         where key custody belongs outside the application database. The first version of this test
--         banned every text column and therefore flagged it, which was the test being wrong rather than
--         the schema.
--
--         What they may NOT hold: a `bytea` column, which is the only shape raw key material would
--         plausibly take here, or a text column that is neither an opaque reference nor a small enum.
--
--         A LIMITATION, stated rather than papered over: no database assertion can prove that the VALUE
--         in an opaque reference is not itself a secret. This test constrains the shape. Whether a given
--         deployment puts a key identifier or a key in that column is an operational property, and it
--         belongs to PS-3/PS-4, which are deferred.
-- ---------------------------------------------------------------------------------------------------
DO $t$
DECLARE v_bytea text; v_text text;
BEGIN
  SELECT string_agg(c.relname || '.' || a.attname, ', ' ORDER BY c.relname, a.attname) INTO v_bytea
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r'
     AND c.relname IN ('mobile_hmac_key_versions','mobile_encryption_key_versions')
     AND a.attnum > 0 AND NOT a.attisdropped
     AND format_type(a.atttypid, a.atttypmod) = 'bytea';
  IF v_bytea IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CID-03 the key-version tables carry bytea column(s): %. Raw key material must '
                    'never live in this database; key custody is external (PS-3/PS-4).', v_bytea;
  END IF;

  -- Text is allowed only as an opaque reference or a constrained enum.
  SELECT string_agg(c.relname || '.' || a.attname, ', ' ORDER BY c.relname, a.attname) INTO v_text
    FROM pg_attribute a
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
   WHERE n.nspname = 'public' AND c.relkind = 'r'
     AND c.relname IN ('mobile_hmac_key_versions','mobile_encryption_key_versions')
     AND a.attnum > 0 AND NOT a.attisdropped
     AND format_type(a.atttypid, a.atttypmod) IN ('text','character varying')
     AND a.attname !~ '_ref$'
     -- a small enum is fine; it is pinned by a CHECK listing its values
     AND NOT EXISTS (SELECT 1 FROM pg_constraint k
                      WHERE k.conrelid = c.oid AND k.contype = 'c'
                        AND pg_get_constraintdef(k.oid) ~ (a.attname || '\s*(=|IN)'));
  IF v_text IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL CID-03 the key-version tables carry unconstrained text column(s): %. Text is '
                    'permitted only as an opaque *_ref or as a CHECK-pinned enum.', v_text;
  END IF;
  RAISE NOTICE 'PASS CID-03 the key-version tables hold no key material: no bytea, and text only as an '
               'opaque *_ref or a CHECK-pinned enum';
END $t$;

-- ---------------------------------------------------------------------------------------------------
-- CID-04  Key-version transitions. Exactly one HMAC key version may be active at a time: two actives
--         means a lookup can resolve under either and a rotation can never be proven complete.
-- ---------------------------------------------------------------------------------------------------
DO $t$
DECLARE v_active integer;
BEGIN
  SELECT count(*) INTO v_active FROM public.mobile_hmac_key_versions WHERE state='active';
  IF v_active <> 1 THEN
    RAISE EXCEPTION 'FAIL CID-04 expected exactly one active HMAC key version, found %', v_active;
  END IF;

  BEGIN
    INSERT INTO public.mobile_hmac_key_versions(key_version, state) VALUES (99, 'active');
    RAISE EXCEPTION 'FAIL CID-04 a SECOND active HMAC key version was accepted';
  EXCEPTION
    WHEN unique_violation OR check_violation OR integrity_constraint_violation THEN
      RAISE NOTICE 'PASS CID-04 a second active HMAC key version is refused';
    WHEN others THEN
      -- Some deployments enforce this with a deferred constraint trigger, which surfaces differently.
      IF position('active' IN SQLERRM) = 0 THEN
        RAISE EXCEPTION 'FAIL CID-04 refused for an unrelated reason: % (%)', SQLERRM, SQLSTATE;
      END IF;
      RAISE NOTICE 'PASS CID-04 a second active HMAC key version is refused (%)', SQLSTATE;
  END;
END $t$;

-- ---------------------------------------------------------------------------------------------------
-- CID-05  Duplicate and collision handling — asserted against where the rule ACTUALLY lives.
--
--         The first version of this test looked for fingerprint uniqueness on student_contact_index and
--         failed. That was the test misreading the design, not a gap. student_contact_index is keyed
--         (student_id, key_version): it answers "what is this student's contact under this key", one row
--         per student per live key version, and it deliberately carries NO uniqueness on the fingerprint.
--
--         Global identity uniqueness lives on enrollment_claim_identity_aliases, as a PARTIAL unique
--         index over (key_version, mobile_hmac, grade_key) restricted to claim states
--         ('active','transfer_pending'). Three properties follow, and all three are deliberate:
--           * uniqueness is per KEY VERSION, so a rotation can hold two live versions at once;
--           * uniqueness is per GRADE, so the same contact may appear in different grades — an identity
--             here is (contact, grade), not contact alone;
--           * uniqueness binds only LIVE claims, so an ended claim does not block re-use, and a
--             transfer_pending claim DOES, which is what stops a transfer being raced by a new claim.
--
--         Worth stating plainly for a reviewer: two students CAN hold the same contact fingerprint in
--         student_contact_index. What they cannot do is hold live claims on it in the same grade under
--         the same key. cp_46_contact_change_race.sh exercises that collision concurrently.
-- ---------------------------------------------------------------------------------------------------
DO $t$
DECLARE v_def text;
BEGIN
  SELECT indexdef INTO v_def
    FROM pg_indexes
   WHERE schemaname='public' AND tablename='enrollment_claim_identity_aliases'
     AND indexdef ~ 'UNIQUE' AND indexdef ~ 'mobile_hmac' AND indexdef ~ 'key_version'
   LIMIT 1;
  IF v_def IS NULL THEN
    RAISE EXCEPTION 'FAIL CID-05 enrollment_claim_identity_aliases has no unique index over '
                    '(key_version, mobile_hmac, ...), so two live claims could share one contact identity';
  END IF;
  IF v_def !~ 'grade_key' THEN
    RAISE EXCEPTION 'FAIL CID-05 the identity uniqueness no longer includes grade_key, which changes what '
                    'an identity means: %', v_def;
  END IF;
  IF v_def !~ 'transfer_pending' THEN
    RAISE EXCEPTION 'FAIL CID-05 the identity uniqueness no longer covers transfer_pending claims, so a '
                    'pending transfer could be raced by a new claim on the same contact: %', v_def;
  END IF;
  RAISE NOTICE 'PASS CID-05 global contact identity is unique per (key version, fingerprint, grade) across '
               'active AND transfer_pending claims';

  IF EXISTS (SELECT 1 FROM pg_indexes
              WHERE schemaname='public' AND tablename='student_contact_index'
                AND indexdef ~ 'UNIQUE' AND indexdef ~ 'mobile_hmac') THEN
    RAISE NOTICE 'PASS CID-05b note: student_contact_index has gained fingerprint uniqueness. That is a '
                 'stricter rule than the design documented here — update this test and the contact '
                 'identity contract rather than leaving the two disagreeing.';
  ELSE
    RAISE NOTICE 'PASS CID-05b student_contact_index is keyed (student_id, key_version) with no fingerprint '
                 'uniqueness, as designed: it answers what a student''s contact is, not who owns a contact';
  END IF;
END $t$;

\echo 'CONTACT CONFIDENTIALITY TESTS COMPLETED (CID-01..CID-05)'
