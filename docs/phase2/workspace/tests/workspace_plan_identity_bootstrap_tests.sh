#!/usr/bin/env bash
# F-05 — the role BOOTSTRAP must validate privileged roles that ALREADY exist, and abort rather than repair.
#
# PostgreSQL roles are cluster-wide. A role named ws_<key>_synth_plan_writer or ws_<key>_plan_migrator can
# exist before workspace_roles_setup_draft.sql runs, created by anyone with CREATEROLE, in any state. The
# earlier bootstrap created the role only `IF NOT EXISTS` and otherwise trusted it as it was.
#
# Each case below creates the unsafe state FIRST, then runs the real bootstrap (the same file CI uses) and
# requires it to FAIL with the named reason. After the failure it also checks that:
#   * nothing was repaired: the unsafe attribute is still there;
#   * nothing was trusted: no identity record exists, so no session can act as a privileged identity.
# A final case shows that the same bootstrap SUCCEEDS on a clean cluster state, so the failures are caused
# by the unsafe state and not by the harness.
#
# Synthetic only (D-014). Usage: bash workspace_plan_identity_bootstrap_tests.sh   (PGHOST/PGUSER as in CI)
set -u
W=docs/phase2/workspace
TPL=f05_bootstrap_template
ok=1; n=0

psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $TPL" >/dev/null
createdb "$TPL"
for f in workspace_schema_draft workspace_activation_transactions workspace_governance_events_draft workspace_archive_transactions workspace_inbox_projection workspace_transfer_freeze workspace_counselor_scope_draft workspace_plan_items_draft workspace_operations_draft; do
  psql -X -q -v ON_ERROR_STOP=1 -d "$TPL" -f "$W/$f.sql" >/dev/null 2>&1 || { echo "FAIL F05-BOOT template load ($f)"; exit 2; }
done

cleanup() {   # $1 = key, $2 = database
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS \"$2\"" >/dev/null 2>&1
  for r in $(psql -X -tA -d postgres -c "SELECT rolname FROM pg_roles WHERE rolname LIKE 'ws\\_$1\\_%'"); do
    psql -X -q -d postgres -c "DROP ROLE \"$r\"" >/dev/null 2>&1 || { echo "FAIL F05-BOOT cleanup could not drop $r"; ok=0; }
  done
}

# case <id> <hex-suffix> <expected message fragment> <setup SQL, with KEY substituted> [<still-unsafe check SQL>]
case_fail() {
  local id="$1" sfx="$2" want="$3" setup="$4" still="${5:-}"
  local key="a10000000000000000000000000f05${sfx}" db="f05_boot_${sfx}"
  n=$((n+1))
  cleanup "$key" "$db"
  psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "${setup//KEY/$key}" >/dev/null || { echo "FAIL $id setup"; ok=0; return; }
  psql -X -q -d postgres -c "CREATE DATABASE \"$db\" TEMPLATE $TPL" >/dev/null
  local out rc
  out="$(psql -X -q -v ON_ERROR_STOP=1 -v workspace_key="$key" -d "$db" -f "$W/workspace_roles_setup_draft.sql" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "FAIL $id bootstrap SUCCEEDED with an unsafe pre-existing role"; ok=0
  elif ! grep -qF "$want" <<<"$out"; then
    echo "FAIL $id bootstrap failed for the wrong reason: $(grep -m1 ERROR <<<"$out")"; ok=0
  else
    local recs
    recs="$(psql -X -tA -d "$db" -c "SELECT count(*) FROM plan_privileged_identities")"
    if [ "$recs" != "0" ]; then echo "FAIL $id an identity record was written ($recs) despite the abort"; ok=0
    elif [ -n "$still" ] && [ "$(psql -X -tA -d postgres -c "${still//KEY/$key}")" != "t" ]; then
      echo "FAIL $id the unsafe role was silently REPAIRED"; ok=0
    else
      echo "PASS $id bootstrap aborted: $(grep -m1 -o 'F-05: [^;]*' <<<"$out" | cut -c1-150)"
    fi
  fi
  cleanup "$key" "$db"
}

case_fail F05-BOOT-01 01 "is unsafe (LOGIN)" \
  "CREATE ROLE ws_KEY_synth_plan_writer LOGIN NOINHERIT" \
  "SELECT rolcanlogin FROM pg_roles WHERE rolname='ws_KEY_synth_plan_writer'"
case_fail F05-BOOT-02 02 "is unsafe (SUPERUSER)" \
  "CREATE ROLE ws_KEY_synth_plan_writer NOLOGIN NOINHERIT SUPERUSER" \
  "SELECT rolsuper FROM pg_roles WHERE rolname='ws_KEY_synth_plan_writer'"
case_fail F05-BOOT-03 03 "is unsafe (CREATEROLE)" \
  "CREATE ROLE ws_KEY_synth_plan_writer NOLOGIN NOINHERIT CREATEROLE" \
  "SELECT rolcreaterole FROM pg_roles WHERE rolname='ws_KEY_synth_plan_writer'"
case_fail F05-BOOT-04 04 "is unsafe (BYPASSRLS)" \
  "CREATE ROLE ws_KEY_synth_plan_writer NOLOGIN NOINHERIT BYPASSRLS" \
  "SELECT rolbypassrls FROM pg_roles WHERE rolname='ws_KEY_synth_plan_writer'"
case_fail F05-BOOT-05 05 "is unsafe (LOGIN)" \
  "CREATE ROLE ws_KEY_plan_migrator LOGIN NOINHERIT" \
  "SELECT rolcanlogin FROM pg_roles WHERE rolname='ws_KEY_plan_migrator'"
case_fail F05-BOOT-06 06 "is unsafe (SUPERUSER)" \
  "CREATE ROLE ws_KEY_plan_migrator NOLOGIN NOINHERIT SUPERUSER" \
  "SELECT rolsuper FROM pg_roles WHERE rolname='ws_KEY_plan_migrator'"
case_fail F05-BOOT-07 07 "is unsafe (CREATEROLE)" \
  "CREATE ROLE ws_KEY_plan_migrator NOLOGIN NOINHERIT CREATEROLE" \
  "SELECT rolcreaterole FROM pg_roles WHERE rolname='ws_KEY_plan_migrator'"
case_fail F05-BOOT-08 08 "is unsafe (BYPASSRLS)" \
  "CREATE ROLE ws_KEY_plan_migrator NOLOGIN NOINHERIT BYPASSRLS" \
  "SELECT rolbypassrls FROM pg_roles WHERE rolname='ws_KEY_plan_migrator'"
case_fail F05-BOOT-09 09 "is unsafe (INHERIT)" \
  "CREATE ROLE ws_KEY_synth_plan_writer NOLOGIN INHERIT" \
  "SELECT rolinherit FROM pg_roles WHERE rolname='ws_KEY_synth_plan_writer'"
# an otherwise clean writer that the runtime already HOLDS (created before the bootstrap)
case_fail F05-BOOT-10 0a "held by ws_" \
  "CREATE ROLE ws_KEY_runtime NOLOGIN NOINHERIT; CREATE ROLE ws_KEY_synth_plan_writer NOLOGIN NOINHERIT; GRANT ws_KEY_synth_plan_writer TO ws_KEY_runtime" \
  "SELECT EXISTS (SELECT 1 FROM pg_auth_members WHERE roleid='ws_KEY_synth_plan_writer'::regrole)"
# an otherwise clean migrator held INDIRECTLY by the worker through a role outside the inventory
case_fail F05-BOOT-11 0b "held by ws_" \
  "CREATE ROLE ws_KEY_worker NOLOGIN NOINHERIT; CREATE ROLE ws_KEY_x_mid NOLOGIN; CREATE ROLE ws_KEY_plan_migrator NOLOGIN NOINHERIT; GRANT ws_KEY_plan_migrator TO ws_KEY_x_mid; GRANT ws_KEY_x_mid TO ws_KEY_worker" \
  "SELECT pg_has_role('ws_KEY_worker','ws_KEY_plan_migrator','MEMBER')"
# a clean privileged role, but an APPLICATION role that already has CREATEROLE: caught by the boundary check
case_fail F05-BOOT-12 0c "pre-existing application role ws_a10000000000000000000000000f050c_runtime_login has unexpected attributes (CREATEROLE)" \
  "CREATE ROLE ws_KEY_runtime_login LOGIN CREATEROLE" \
  "SELECT rolcreaterole FROM pg_roles WHERE rolname='ws_KEY_runtime_login'"

# F-05 follow-up: EVERY pre-existing application role is checked against its expected attributes, and any
# pre-existing path to an OWNER role aborts the bootstrap.
case_fail F05-BOOT-15 0d "pre-existing application role ws_a10000000000000000000000000f050d_runtime has unexpected attributes (LOGIN (expected NOLOGIN))" \
  "CREATE ROLE ws_KEY_runtime LOGIN NOINHERIT" \
  "SELECT rolcanlogin FROM pg_roles WHERE rolname='ws_KEY_runtime'"
case_fail F05-BOOT-16 0e "pre-existing application role ws_a10000000000000000000000000f050e_table_owner has unexpected attributes (INHERIT (expected NOINHERIT))" \
  "CREATE ROLE ws_KEY_table_owner NOLOGIN INHERIT" \
  "SELECT rolinherit FROM pg_roles WHERE rolname='ws_KEY_table_owner'"
case_fail F05-BOOT-17 0f "pre-existing application role ws_a10000000000000000000000000f050f_worker_login has unexpected attributes (NOLOGIN (expected LOGIN))" \
  "CREATE ROLE ws_KEY_worker_login NOLOGIN INHERIT" \
  "SELECT NOT rolcanlogin FROM pg_roles WHERE rolname='ws_KEY_worker_login'"
case_fail F05-BOOT-18 10 "pre-existing application role ws_a10000000000000000000000000f0510_governance_owner has unexpected attributes (CREATEDB)" \
  "CREATE ROLE ws_KEY_governance_owner NOLOGIN NOINHERIT CREATEDB" \
  "SELECT rolcreatedb FROM pg_roles WHERE rolname='ws_KEY_governance_owner'"
# attributes all correct, but a pre-existing CHAIN runtime_login -> x_mid -> function_owner
case_fail F05-BOOT-19 11 "application role ws_a10000000000000000000000000f0511_runtime_login can reach owner ws_a10000000000000000000000000f0511_function_owner via ws_a10000000000000000000000000f0511_runtime_login -> ws_a10000000000000000000000000f0511_x_mid -> ws_a10000000000000000000000000f0511_function_owner" \
  "CREATE ROLE ws_KEY_function_owner NOLOGIN NOINHERIT; CREATE ROLE ws_KEY_x_mid NOLOGIN NOINHERIT; CREATE ROLE ws_KEY_runtime_login LOGIN INHERIT; GRANT ws_KEY_function_owner TO ws_KEY_x_mid; GRANT ws_KEY_x_mid TO ws_KEY_runtime_login" \
  "SELECT pg_has_role('ws_KEY_runtime_login','ws_KEY_function_owner','MEMBER')"
# a pre-existing nested chain exporter -> a -> b -> governance_owner with ADMIN only on the last link
case_fail F05-BOOT-20 12 "application role ws_a10000000000000000000000000f0512_exporter can reach owner ws_a10000000000000000000000000f0512_governance_owner via ws_a10000000000000000000000000f0512_exporter -> ws_a10000000000000000000000000f0512_x_a -> ws_a10000000000000000000000000f0512_x_b -> ws_a10000000000000000000000000f0512_governance_owner" \
  "CREATE ROLE ws_KEY_governance_owner NOLOGIN NOINHERIT; CREATE ROLE ws_KEY_x_a NOLOGIN; CREATE ROLE ws_KEY_x_b NOLOGIN; CREATE ROLE ws_KEY_exporter NOLOGIN NOINHERIT; GRANT ws_KEY_governance_owner TO ws_KEY_x_b WITH ADMIN TRUE, INHERIT FALSE, SET FALSE; GRANT ws_KEY_x_b TO ws_KEY_x_a; GRANT ws_KEY_x_a TO ws_KEY_exporter" \
  "SELECT pg_has_role('ws_KEY_exporter','ws_KEY_governance_owner','MEMBER')"

# The same bootstrap on a clean state succeeds, records both identities and reports a verified boundary.
key=a10000000000000000000000000f05ff; db=f05_boot_ff; n=$((n+2))
cleanup "$key" "$db"
psql -X -q -d postgres -c "CREATE DATABASE \"$db\" TEMPLATE $TPL" >/dev/null
out="$(psql -X -q -v ON_ERROR_STOP=1 -v workspace_key="$key" -d "$db" -f "$W/workspace_roles_setup_draft.sql" 2>&1)"; rc=$?
recs="$(psql -X -tA -d "$db" -c "SELECT count(*) FROM plan_privileged_identities" 2>/dev/null)"
if [ "$rc" -eq 0 ] && [ "$recs" = "2" ] && grep -q "F-05: plan identity boundary verified" <<<"$out"; then
  echo "PASS F05-BOOT-13 the same bootstrap on a clean state succeeds and records both identities"
else
  echo "FAIL F05-BOOT-13 clean bootstrap (rc=$rc, records=$recs): $(grep -m1 ERROR <<<"$out")"; ok=0
fi
# Re-running the bootstrap over the roles IT created (now pre-existing) is accepted: validation passes them.
out="$(psql -X -q -v ON_ERROR_STOP=1 -v workspace_key="$key" -d "$db" -f "$W/workspace_roles_setup_draft.sql" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then echo "PASS F05-BOOT-14 a re-run over safe pre-existing roles is accepted (validated, not recreated)"
else echo "FAIL F05-BOOT-14 re-run over safe roles failed: $(grep -m1 ERROR <<<"$out")"; ok=0; fi
cleanup "$key" "$db"
psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $TPL" >/dev/null

[ "$ok" = "1" ] || exit 1
echo "PLAN IDENTITY BOOTSTRAP TESTS (F-05) COMPLETED ($n cases)"
