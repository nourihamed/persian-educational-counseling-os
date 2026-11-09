-- Control Plane role/privilege catalog assertions. Run after cp_06_role_privileges_draft.sql.
\set ON_ERROR_STOP on
DO $role_test$
DECLARE n integer; bad text;
BEGIN
  SELECT count(*) INTO n
  FROM pg_roles
  WHERE rolname IN ('cp_table_owner','cp_function_owner','cp_runtime','cp_transfer_executor','cp_rotation_executor')
    AND (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls);
  IF n<>0 THEN RAISE EXCEPTION 'FAIL CP-ROLE-01 one or more CP roles have forbidden login/elevated attributes'; END IF;

  SELECT string_agg(c.relname,',') INTO bad
  FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
  WHERE ns.nspname='public'
    AND c.relname IN ('workspaces','platform_students','student_contact_index','mobile_encryption_key_versions',
      'mobile_hmac_key_versions','identity_write_gate','student_ownership','enrollment_claims',
      'enrollment_claim_identity_aliases','transfer_cases','transfer_approvals','command_log',
      'inbox_events','outbox_events','ownership_history','transfer_state_transitions')
    AND pg_get_userbyid(c.relowner)<>'cp_table_owner';
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL CP-ROLE-02 tables not owned by cp_table_owner: %',bad; END IF;

  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
  WHERE ns.nspname='public'
    AND p.proname IN ('switch_student_ownership','request_transfer_case_idempotent',
      'begin_identity_hmac_rotation','complete_identity_hmac_rotation','retire_identity_hmac_version')
    AND pg_get_userbyid(p.proowner)<>'cp_function_owner';
  IF n<>0 THEN RAISE EXCEPTION 'FAIL CP-ROLE-03 SECURITY DEFINER function owner mismatch'; END IF;

  IF has_table_privilege('cp_runtime','public.student_ownership','SELECT')
     OR has_table_privilege('cp_runtime','public.student_ownership','INSERT')
     OR has_table_privilege('cp_runtime','public.student_ownership','UPDATE')
     OR has_table_privilege('cp_runtime','public.student_ownership','DELETE')
     OR has_table_privilege('cp_transfer_executor','public.student_ownership','UPDATE')
     OR has_table_privilege('cp_rotation_executor','public.student_ownership','UPDATE') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-04 runtime/executor has direct protected-table access';
  END IF;

  IF has_function_privilege('cp_runtime','public.switch_student_ownership(uuid)','EXECUTE')
     OR has_function_privilege('cp_runtime','public.begin_identity_hmac_rotation()','EXECUTE')
     OR has_function_privilege('cp_transfer_executor','public.begin_identity_hmac_rotation()','EXECUTE')
     OR has_function_privilege('cp_rotation_executor','public.switch_student_ownership(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-05 privileged function scope is too broad';
  END IF;

  IF NOT has_function_privilege('cp_transfer_executor','public.switch_student_ownership(uuid)','EXECUTE')
     OR NOT has_function_privilege('cp_transfer_executor','public.request_transfer_case_idempotent(text,bytea,uuid,uuid,uuid,uuid,bigint,text)','EXECUTE')
     OR NOT has_function_privilege('cp_rotation_executor','public.begin_identity_hmac_rotation()','EXECUTE')
     OR NOT has_function_privilege('cp_rotation_executor','public.complete_identity_hmac_rotation(integer)','EXECUTE')
     OR NOT has_function_privilege('cp_rotation_executor','public.retire_identity_hmac_version(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-06 designated executor lacks its required function privilege';
  END IF;

  IF pg_has_role('cp_function_owner','cp_table_owner','MEMBER')
     OR pg_has_role('cp_runtime','cp_function_owner','MEMBER')
     OR pg_has_role('cp_transfer_executor','cp_function_owner','MEMBER')
     OR pg_has_role('cp_rotation_executor','cp_function_owner','MEMBER') THEN
    RAISE EXCEPTION 'FAIL CP-ROLE-07 function/table owner role inheritance is forbidden';
  END IF;

  SELECT count(*) INTO n
  FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
  CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) acl
  WHERE ns.nspname='public'
    AND p.proname IN ('switch_student_ownership','request_transfer_case_idempotent',
      'begin_identity_hmac_rotation','complete_identity_hmac_rotation','retire_identity_hmac_version')
    AND acl.grantee=0 AND acl.privilege_type='EXECUTE';
  IF n<>0 THEN RAISE EXCEPTION 'FAIL CP-ROLE-08 PUBLIC retains EXECUTE on privileged functions'; END IF;

  RAISE NOTICE 'PASS CP-ROLE-01..08 least-privilege catalog assertions';
END $role_test$;
