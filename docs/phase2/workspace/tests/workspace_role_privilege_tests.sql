\set ON_ERROR_STOP on
\if :{?workspace_key}
\else
  \echo 'ERROR: pass -v workspace_key=<workspace-key>'
  \quit 3
\endif
\if :{?other_workspace_key}
\else
  \echo 'ERROR: pass -v other_workspace_key=<other-workspace-key>'
  \quit 3
\endif
\if :{?other_database}
\else
  \echo 'ERROR: pass -v other_database=<other-database-name>'
  \quit 3
\endif

SET app.workspace_key = :'workspace_key';
SET app.other_workspace_key = :'other_workspace_key';
SET app.other_database = :'other_database';

DO $role_test$
DECLARE
  k text := current_setting('app.workspace_key');
  other_k text := current_setting('app.other_workspace_key');
  other_db text := current_setting('app.other_database');
  table_owner text := 'ws_'||k||'_table_owner';
  function_owner text := 'ws_'||k||'_function_owner';
  runtime_role text := 'ws_'||k||'_runtime';
  worker_role text := 'ws_'||k||'_worker';
  exporter_role text := 'ws_'||k||'_exporter';
  runtime_login text := 'ws_'||k||'_runtime_login';
  worker_login text := 'ws_'||k||'_worker_login';
  exporter_login text := 'ws_'||k||'_exporter_login';
  other_runtime_login text := 'ws_'||other_k||'_runtime_login';
  n integer;
  bad text;
BEGIN
  IF k !~ '^[0-9a-f]{32}$' OR other_k !~ '^[0-9a-f]{32}$' OR other_k=k THEN
    RAISE EXCEPTION 'FAIL WS-ROLE-00 invalid or non-distinct workspace role keys';
  END IF;

  SELECT count(*) INTO n FROM pg_roles
   WHERE rolname IN (table_owner,function_owner,runtime_role,worker_role,exporter_role,
                     runtime_login,worker_login,exporter_login);
  IF n<>8 THEN RAISE EXCEPTION 'FAIL WS-ROLE-01 expected eight per-Workspace roles, found %',n; END IF;

  SELECT count(*) INTO n FROM pg_roles
   WHERE rolname IN (table_owner,function_owner,runtime_role,worker_role,exporter_role)
     AND (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls);
  IF n<>0 THEN RAISE EXCEPTION 'FAIL WS-ROLE-02 group/owner role has login or elevated attributes'; END IF;

  SELECT count(*) INTO n FROM pg_roles
   WHERE rolname IN (runtime_login,worker_login,exporter_login)
     AND (NOT rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls);
  IF n<>0 THEN RAISE EXCEPTION 'FAIL WS-ROLE-03 service login has forbidden attributes'; END IF;

  IF NOT pg_has_role(runtime_login,runtime_role,'MEMBER')
     OR NOT pg_has_role(worker_login,worker_role,'MEMBER')
     OR NOT pg_has_role(exporter_login,exporter_role,'MEMBER') THEN
    RAISE EXCEPTION 'FAIL WS-ROLE-04 service login/group-role membership missing';
  END IF;

  SELECT count(*) INTO n
    FROM pg_auth_members m
    JOIN pg_roles member_role ON member_role.oid=m.member
    JOIN pg_roles granted_role ON granted_role.oid=m.roleid
   WHERE member_role.rolname IN (runtime_login,worker_login,exporter_login)
     AND granted_role.rolname IN (table_owner,function_owner);
  IF n<>0 THEN RAISE EXCEPTION 'FAIL WS-ROLE-05 service login can assume owner/function-owner role'; END IF;

  SELECT string_agg(c.relname,',') INTO bad
    FROM pg_class c JOIN pg_namespace ns ON ns.oid=c.relnamespace
   WHERE ns.nspname='public' AND c.relkind IN ('r','p','S')
     AND pg_get_userbyid(c.relowner)<>table_owner;
  IF bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL WS-ROLE-06 objects not owned by Workspace table owner: %',bad; END IF;

  SELECT count(*) INTO n
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid=p.pronamespace
   WHERE ns.nspname='public' AND pg_get_userbyid(p.proowner)<>function_owner;
  IF n<>0 THEN RAISE EXCEPTION 'FAIL WS-ROLE-07 functions not owned by non-login function owner: %',n; END IF;

  IF has_schema_privilege(runtime_role,'public','CREATE')
     OR has_schema_privilege(worker_role,'public','CREATE')
     OR has_schema_privilege(exporter_role,'public','CREATE') THEN
    RAISE EXCEPTION 'FAIL WS-ROLE-08 runtime/worker/exporter can CREATE in public schema';
  END IF;

  IF NOT has_table_privilege(runtime_role,'public.students','SELECT')
     OR NOT has_table_privilege(runtime_role,'public.workspace_memberships','SELECT')
     OR NOT has_table_privilege(runtime_role,'public.membership_roles','SELECT')
     OR NOT has_table_privilege(runtime_role,'public.membership_permissions','SELECT')
     OR NOT has_table_privilege(runtime_role,'public.counselor_assignments','SELECT')
     OR NOT has_table_privilege(runtime_role,'public.student_guardian_links','SELECT')
     OR NOT has_table_privilege(runtime_role,'public.guardian_permissions','SELECT')
     OR has_table_privilege(runtime_role,'public.workspace_memberships','INSERT')
     OR has_table_privilege(runtime_role,'public.workspace_memberships','UPDATE')
     OR has_table_privilege(runtime_role,'public.membership_roles','INSERT')
     OR has_table_privilege(runtime_role,'public.membership_roles','UPDATE')
     OR has_table_privilege(runtime_role,'public.membership_roles','DELETE')
     OR has_table_privilege(runtime_role,'public.membership_permissions','INSERT')
     OR has_table_privilege(runtime_role,'public.membership_permissions','UPDATE')
     OR has_table_privilege(runtime_role,'public.membership_permissions','DELETE')
     OR has_table_privilege(runtime_role,'public.branches','INSERT')
     OR has_table_privilege(runtime_role,'public.branches','UPDATE')
     OR has_table_privilege(runtime_role,'public.counselor_assignments','INSERT')
     OR has_table_privilege(runtime_role,'public.counselor_assignments','UPDATE')
     OR has_table_privilege(runtime_role,'public.student_guardian_links','INSERT')
     OR has_table_privilege(runtime_role,'public.student_guardian_links','UPDATE')
     OR has_table_privilege(runtime_role,'public.guardian_permissions','INSERT')
     OR has_table_privilege(runtime_role,'public.guardian_permissions','UPDATE')
     OR has_table_privilege(runtime_role,'public.workspace_memberships','DELETE')
     OR has_table_privilege(runtime_role,'public.branches','DELETE')
     OR has_table_privilege(runtime_role,'public.counselor_assignments','DELETE')
     OR has_table_privilege(runtime_role,'public.student_guardian_links','DELETE')
     OR has_table_privilege(runtime_role,'public.guardian_permissions','DELETE')
     OR has_table_privilege(function_owner,'public.workspace_memberships','INSERT')
     OR has_table_privilege(function_owner,'public.workspace_memberships','UPDATE')
     OR has_table_privilege(function_owner,'public.membership_roles','INSERT')
     OR has_table_privilege(function_owner,'public.membership_roles','UPDATE')
     OR has_table_privilege(function_owner,'public.membership_permissions','INSERT')
     OR has_table_privilege(function_owner,'public.membership_permissions','UPDATE')
     OR has_table_privilege(function_owner,'public.counselor_assignments','UPDATE')
     OR has_table_privilege(function_owner,'public.student_guardian_links','UPDATE')
     OR has_table_privilege(function_owner,'public.guardian_permissions','UPDATE')
     OR NOT has_column_privilege(function_owner,'public.students','student_id','UPDATE')
     OR has_column_privilege(function_owner,'public.students','display_name','UPDATE')
     OR has_column_privilege(function_owner,'public.students','lifecycle_state','UPDATE')
     OR NOT has_column_privilege(function_owner,'public.enrollments','state','UPDATE')
     OR NOT has_column_privilege(function_owner,'public.enrollments','started_at','UPDATE')
     OR NOT has_column_privilege(function_owner,'public.workspace_capacity_counters','current_value','UPDATE')
     OR NOT has_column_privilege(function_owner,'public.credit_wallets','wallet_id','UPDATE')
     OR NOT has_column_privilege(function_owner,'public.credit_transactions','transaction_id','UPDATE')
     OR NOT has_column_privilege(function_owner,'public.activation_command_log','idempotency_key','UPDATE')
     OR has_table_privilege(runtime_role,'public.enrollments','UPDATE')
     OR has_table_privilege(runtime_role,'public.enrollments','DELETE')
     OR has_table_privilege(runtime_role,'public.students','DELETE')
     OR has_column_privilege(runtime_role,'public.students','lifecycle_state','UPDATE')
     OR NOT has_column_privilege(runtime_role,'public.students','display_name','UPDATE')
     OR has_table_privilege(runtime_role,'public.credit_transactions','INSERT')
     OR has_table_privilege(runtime_role,'public.capacity_events','INSERT')
     OR has_table_privilege(runtime_role,'public.activation_command_log','INSERT')
     OR has_table_privilege(runtime_role,'public.workspace_governance_events','SELECT')
     OR has_table_privilege(runtime_role,'public.workspace_governance_events','INSERT')
     OR has_table_privilege(function_owner,'public.workspace_governance_events','INSERT')
     OR has_function_privilege(runtime_role,'public.append_workspace_governance_event(uuid,text,uuid,text,uuid,text,text,text,text,bytea,jsonb,timestamptz)','EXECUTE')
     OR has_table_privilege(runtime_role,'public.students','TRUNCATE')
     OR NOT has_table_privilege(function_owner,'public.audit_events','INSERT')
     OR has_table_privilege(function_owner,'public.audit_events','UPDATE') THEN
    RAISE EXCEPTION 'FAIL WS-ROLE-09 runtime table privileges are too broad or incomplete';
  END IF;

  IF NOT has_table_privilege(worker_role,'public.in_app_notifications','UPDATE')
     OR has_table_privilege(worker_role,'public.students','SELECT')
     OR has_table_privilege(exporter_role,'public.students','SELECT') THEN
    RAISE EXCEPTION 'FAIL WS-ROLE-10 worker/exporter privileges exceed their scopes';
  END IF;

  IF NOT has_function_privilege(runtime_role,
       'public.activate_student_enrollment(text,uuid,uuid,bigint,bigint,uuid)','EXECUTE')
     OR has_function_privilege(runtime_role,
       'public.adjust_workspace_capacity(text,integer,text,uuid,uuid,text)','EXECUTE')
     OR NOT has_function_privilege(function_owner,
       'public.adjust_workspace_capacity(text,integer,text,uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL WS-ROLE-11 activation/capacity function grants are incorrect';
  END IF;

  IF NOT has_database_privilege(runtime_login,current_database(),'CONNECT')
     OR has_database_privilege(runtime_login,other_db,'CONNECT')
     OR has_database_privilege(other_runtime_login,current_database(),'CONNECT') THEN
    RAISE EXCEPTION 'FAIL WS-ROLE-12 per-Workspace database CONNECT boundary is incorrect';
  END IF;

  SELECT count(*) INTO n
    FROM pg_proc p
    CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) acl
   WHERE p.oid IN (
     'public.activate_student_enrollment(text,uuid,uuid,bigint,bigint,uuid)'::regprocedure,
     'public.adjust_workspace_capacity(text,integer,text,uuid,uuid,text)'::regprocedure
   )
     AND acl.grantee=0 AND acl.privilege_type='EXECUTE';
  IF n<>0 THEN RAISE EXCEPTION 'FAIL WS-ROLE-13 PUBLIC retains EXECUTE on privileged Workspace functions'; END IF;

  RAISE NOTICE 'PASS WS-ROLE-01..13 per-Workspace ownership, role, grant and database isolation assertions';
END $role_test$;
