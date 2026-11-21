-- WS-ISO-01 — ROW-LEVEL SECURITY bound to the VERIFIED principal (closes ISO-GAP-01..03 at schema level).
-- NOT a migration. Draft SQL. SYNTHETIC ONLY (D-014).
-- Apply LAST among the drafts (after every student-scoped table exists) and BEFORE
-- workspace_roles_setup_draft.sql, which fills iso_application_roles and grants the principal functions.
--
-- THE RULE
--   For an APPLICATION role — the runtime, worker and exporter service roles and their login identities —
--   a row of any student-scoped table is visible or writable only when the VERIFIED principal of the
--   current transaction is a counselor who may reach that row's student (the counselor boundary of
--   workspace_counselor_scope_draft.sql, unchanged). No principal: no row. A student principal: no row
--   either — what a student may read directly is not decided, so it is denied (fail-closed).
--   private_to_author counselor notes are additionally visible to their author only.
--   A plan version or a counselor note written by an application role must name the verified principal
--   as its author.
--
-- WHO IT DOES NOT APPLY TO, AND WHY
--   Roles outside iso_application_roles: the NOLOGIN owners, whose reviewed SECURITY DEFINER functions are
--   the legitimate cross-student paths (activation, archive, transfer, ledgers), and the NOLOGIN synthetic
--   test identities, which are governed by their own guards. ISO-RLS-C3 classifies every role holding a
--   privilege on a student-scoped table and FAILS on any role it cannot classify, so a new role cannot slip
--   between the two lists unnoticed. A superuser bypasses RLS by PostgreSQL design (SEC-08 limitation).
--
-- WHY ENABLE + FORCE
--   FORCE makes the policies apply to the table owner as well, so ownership is not an implicit bypass; the
--   owner is then excluded by the same explicit role rule as every other trusted identity.
BEGIN;

-- The application roles of this Workspace. Filled by workspace_roles_setup_draft.sql from its own inventory.
CREATE TABLE iso_application_roles (
  role_name name PRIMARY KEY
);

-- Does the RLS rule apply to the current identity? Identity by name, as PostgreSQL sets current_user —
-- never membership (the F-05 lesson). SET ROLE from a login to its service role keeps it in the list.
-- current_user and NOT session_user: inside a reviewed SECURITY DEFINER command current_user is that
-- function's NOLOGIN owner, and those commands are the legitimate cross-student paths. A definer that
-- exposes student rows to its caller is therefore a reviewed boundary of its own (SEC-07 governs which
-- definers an application role may execute).
-- The role is passed IN by the policy expression, which PostgreSQL evaluates as the querying role, so
-- `current_user` there is the caller. Inside this SECURITY DEFINER function current_user would be the
-- owner instead, which is why the function cannot read it itself. Calling it directly with another name
-- only answers a question about that name; it grants nothing.
CREATE FUNCTION iso_rls_applies(p_role name) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $body$
  SELECT EXISTS (SELECT 1 FROM public.iso_application_roles a WHERE a.role_name = p_role);
$body$;

-- May the verified principal reach the owner of this row? Resolution is the transfer barrier's own
-- resolver, so the RLS boundary, the write barrier and counselor_may_access_row cannot disagree.
-- SECURITY DEFINER so that resolving the owner is not itself filtered by RLS on the tables it reads.
CREATE FUNCTION iso_principal_may_reach(p_kind text, p_key uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $body$
  SELECT public.counselor_may_access_student(public.current_principal_membership(),
                                             public.resolve_student_for_barrier(p_kind, p_key));
$body$;
-- EXECUTE stays with PUBLIC on purpose, like assert_student_not_frozen (SEC-07 allowlist): every role that
-- reads a student-scoped table evaluates these policies, and both functions answer only about the CALLER'S
-- OWN principal. Without a verified principal iso_principal_may_reach is always false.

-- One generator for every student-scoped table, so a table cannot be missed (ISO-RLS-C1 audits it).
DO $rls$
DECLARE r record; v_pred text;
BEGIN
  FOR r IN SELECT table_name, key_column, key_kind FROM public.student_scoped_tables ORDER BY table_name LOOP
    v_pred := format('(NOT public.iso_rls_applies(current_user) OR public.iso_principal_may_reach(%L, %I))',
                     r.key_kind, r.key_column);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.table_name);
    EXECUTE format('ALTER TABLE public.%I FORCE ROW LEVEL SECURITY', r.table_name);
    EXECUTE format('CREATE POLICY iso_counselor_scope ON public.%I AS PERMISSIVE FOR ALL TO PUBLIC '
                   'USING %s WITH CHECK %s', r.table_name, v_pred, v_pred);
  END LOOP;
END $rls$;

-- Private notes: their author only (ISO-GAP-02).
CREATE POLICY iso_private_note_author ON counselor_notes AS RESTRICTIVE FOR SELECT TO PUBLIC
  USING (NOT public.iso_rls_applies(current_user) OR visibility <> 'private_to_author'
         OR author_membership_id = public.current_principal_membership());
-- Authorship: an application role cannot write a note or a plan version in another counselor's name.
CREATE POLICY iso_note_author_is_principal ON counselor_notes AS RESTRICTIVE FOR INSERT TO PUBLIC
  WITH CHECK (NOT public.iso_rls_applies(current_user) OR author_membership_id = public.current_principal_membership());
-- (The author column exists once workspace_plan_items_draft.sql is loaded; without it there is no author to bind.)
DO $pv$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.student_plan_versions'::regclass
                AND attname = 'created_by_membership_id' AND NOT attisdropped) THEN
    CREATE POLICY iso_plan_version_author_is_principal ON student_plan_versions AS RESTRICTIVE FOR INSERT TO PUBLIC
      WITH CHECK (NOT public.iso_rls_applies(current_user) OR created_by_membership_id = public.current_principal_membership());
  END IF;
END $pv$;

COMMIT;
