-- Control Plane role/privilege catalog assertions. Run after cp_06_role_privileges_draft.sql.
\set ON_ERROR_STOP on
DO $role_test$
DECLARE n integer; bad text;
BEGIN
  SELECT count(*) INTO n FROM pg_roles
   WHERE rolname IN ('cp_table_owner','cp_transfer_function_owner','cp_rotation_function_owner',
     'cp_identity_admission_function_owner','cp_runtime','cp_transfer_executor',
     'cp_rotation_executor','cp_identity_admission_executor');
  IF n<>8 THEN RAISE EXCEPTION 'FAIL CP-ROLE-00 expected eight separated roles'; END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_function_owner') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-00 legacy shared function owner must not exist';
  END IF;

  SELECT count(*) INTO n FROM pg_roles
   WHERE rolname IN ('cp_table_owner','cp_transfer_function_owner','cp_rotation_function_owner',
     'cp_identity_admission_function_owner','cp_runtime','cp_transfer_executor',
     'cp_rotation_executor','cp_identity_admission_executor')
     AND (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls OR rolreplication);
  IF n<>0 THEN RAISE EXCEPTION 'FAIL CP-ROLE-01 one or more CP roles have forbidden attributes'; END IF;

  SELECT string_agg(c.relname,',') INTO bad
  FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
  WHERE ns.nspname='public'
    AND c.relname IN ('workspaces','platform_students','student_contact_index','mobile_encryption_key_versions',
      'mobile_hmac_key_versions','identity_write_gate','student_ownership','enrollment_claims',
      'enrollment_claim_identity_aliases','transfer_cases','transfer_approvals','command_log',
      'inbox_events','outbox_events','ownership_history','transfer_state_transitions','identity_admission_commands')
    AND pg_get_userbyid(c.relowner)<>'cp_table_owner';
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL CP-ROLE-02 tables not owned by cp_table_owner: %',bad; END IF;

  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='public' AND p.proname IN ('switch_student_ownership','request_transfer_case_idempotent')
      AND pg_get_userbyid(p.proowner)<>'cp_transfer_function_owner')
     OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='public' AND p.proname IN ('begin_identity_hmac_rotation','complete_identity_hmac_rotation','retire_identity_hmac_version')
      AND pg_get_userbyid(p.proowner)<>'cp_rotation_function_owner')
     OR EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
    WHERE ns.nspname='public' AND p.proname='admit_student_identity_claim'
      AND pg_get_userbyid(p.proowner)<>'cp_identity_admission_function_owner') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-03 SECURITY DEFINER function family owner mismatch';
  END IF;

  IF has_table_privilege('cp_runtime','public.student_ownership','SELECT')
     OR has_table_privilege('cp_runtime','public.student_ownership','INSERT')
     OR has_table_privilege('cp_runtime','public.student_ownership','UPDATE')
     OR has_table_privilege('cp_runtime','public.student_ownership','DELETE')
     OR has_table_privilege('cp_transfer_executor','public.student_ownership','UPDATE')
     OR has_table_privilege('cp_rotation_executor','public.student_ownership','UPDATE')
     OR has_table_privilege('cp_identity_admission_executor','public.student_ownership','SELECT')
     OR has_table_privilege('cp_identity_admission_executor','public.student_ownership','INSERT')
     OR has_table_privilege('cp_identity_admission_executor','public.student_ownership','UPDATE')
     OR has_table_privilege('cp_identity_admission_executor','public.student_ownership','DELETE') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-04 runtime/executor has direct protected-table access';
  END IF;

  -- Function owners must not inherit table ownership or one another.
  IF pg_has_role('cp_transfer_function_owner','cp_table_owner','MEMBER')
     OR pg_has_role('cp_rotation_function_owner','cp_table_owner','MEMBER')
     OR pg_has_role('cp_identity_admission_function_owner','cp_table_owner','MEMBER')
     OR pg_has_role('cp_transfer_function_owner','cp_rotation_function_owner','MEMBER')
     OR pg_has_role('cp_transfer_function_owner','cp_identity_admission_function_owner','MEMBER')
     OR pg_has_role('cp_rotation_function_owner','cp_transfer_function_owner','MEMBER')
     OR pg_has_role('cp_rotation_function_owner','cp_identity_admission_function_owner','MEMBER')
     OR pg_has_role('cp_identity_admission_function_owner','cp_transfer_function_owner','MEMBER')
     OR pg_has_role('cp_identity_admission_function_owner','cp_rotation_function_owner','MEMBER')
     OR pg_has_role('cp_transfer_executor','cp_transfer_function_owner','MEMBER')
     OR pg_has_role('cp_rotation_executor','cp_rotation_function_owner','MEMBER')
     OR pg_has_role('cp_identity_admission_executor','cp_identity_admission_function_owner','MEMBER')
     OR pg_has_role('cp_runtime','cp_table_owner','MEMBER') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-05 owner/executor role inheritance is forbidden';
  END IF;

  -- Each function owner has only its own data family, not blanket DML.
  IF NOT has_table_privilege('cp_transfer_function_owner','public.transfer_cases','UPDATE')
     OR NOT has_table_privilege('cp_transfer_function_owner','public.student_ownership','UPDATE')
     OR NOT has_table_privilege('cp_transfer_function_owner','public.command_log','INSERT')
     OR has_table_privilege('cp_transfer_function_owner','public.identity_write_gate','UPDATE')
     OR has_table_privilege('cp_transfer_function_owner','public.platform_students','INSERT')
     OR has_table_privilege('cp_transfer_function_owner','public.mobile_hmac_key_versions','UPDATE') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-06 transfer owner privilege boundary is incorrect';
  END IF;
  IF NOT has_table_privilege('cp_rotation_function_owner','public.identity_write_gate','UPDATE')
     OR NOT has_table_privilege('cp_rotation_function_owner','public.mobile_hmac_key_versions','UPDATE')
     OR NOT has_table_privilege('cp_rotation_function_owner','public.student_contact_index','DELETE')
     OR has_table_privilege('cp_rotation_function_owner','public.transfer_cases','UPDATE')
     OR has_table_privilege('cp_rotation_function_owner','public.student_ownership','UPDATE')
     OR has_table_privilege('cp_rotation_function_owner','public.platform_students','INSERT') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-07 rotation owner privilege boundary is incorrect';
  END IF;
  IF NOT has_table_privilege('cp_identity_admission_function_owner','public.platform_students','INSERT')
     OR NOT has_table_privilege('cp_identity_admission_function_owner','public.enrollment_claims','INSERT')
     OR NOT has_table_privilege('cp_identity_admission_function_owner','public.identity_admission_commands','INSERT')
     OR has_table_privilege('cp_identity_admission_function_owner','public.transfer_cases','UPDATE')
     OR has_table_privilege('cp_identity_admission_function_owner','public.identity_write_gate','UPDATE')
     OR has_table_privilege('cp_identity_admission_function_owner','public.command_log','INSERT') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-08 identity admission owner privilege boundary is incorrect';
  END IF;

  IF (SELECT pg_get_userbyid(relowner) FROM pg_class WHERE oid='public.ownership_history_history_id_seq'::regclass)<>'cp_table_owner'
     OR NOT has_sequence_privilege('cp_transfer_function_owner','public.ownership_history_history_id_seq','USAGE')
     OR has_sequence_privilege('cp_rotation_function_owner','public.ownership_history_history_id_seq','USAGE')
     OR has_sequence_privilege('cp_identity_admission_function_owner','public.ownership_history_history_id_seq','USAGE')
     OR has_sequence_privilege('cp_runtime','public.ownership_history_history_id_seq','USAGE') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-09 sequence ownership/grants are not scoped to transfer owner';
  END IF;

  IF NOT has_function_privilege('cp_transfer_executor','public.switch_student_ownership(uuid)','EXECUTE')
     OR NOT has_function_privilege('cp_transfer_executor','public.request_transfer_case_idempotent(text,bytea,uuid,uuid,uuid,uuid,bigint,text)','EXECUTE')
     OR has_function_privilege('cp_transfer_executor','public.begin_identity_hmac_rotation()','EXECUTE')
     OR NOT has_function_privilege('cp_rotation_executor','public.begin_identity_hmac_rotation()','EXECUTE')
     OR NOT has_function_privilege('cp_rotation_executor','public.complete_identity_hmac_rotation(integer)','EXECUTE')
     OR NOT has_function_privilege('cp_rotation_executor','public.retire_identity_hmac_version(integer)','EXECUTE')
     OR has_function_privilege('cp_rotation_executor','public.switch_student_ownership(uuid)','EXECUTE')
     OR NOT has_function_privilege('cp_identity_admission_executor','public.admit_student_identity_claim(text,bytea,uuid,uuid,uuid,text,bytea,integer,jsonb)','EXECUTE')
     OR has_function_privilege('cp_identity_admission_executor','public.switch_student_ownership(uuid)','EXECUTE')
     OR has_function_privilege('cp_identity_admission_executor','public.begin_identity_hmac_rotation()','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-10 executor function scope is incorrect';
  END IF;

  SELECT count(*) INTO n
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) acl
  WHERE ns.nspname='public'
    AND p.proname IN ('switch_student_ownership','request_transfer_case_idempotent',
      'begin_identity_hmac_rotation','complete_identity_hmac_rotation','retire_identity_hmac_version',
      'admit_student_identity_claim')
    AND acl.grantee=0 AND acl.privilege_type='EXECUTE';
  IF n<>0 THEN RAISE EXCEPTION 'FAIL CP-ROLE-11 PUBLIC retains EXECUTE on privileged functions'; END IF;

  RAISE NOTICE 'PASS CP-ROLE-01..11 split-owner least-privilege catalog assertions';
END $role_test$;
