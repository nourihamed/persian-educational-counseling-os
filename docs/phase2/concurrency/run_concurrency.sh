#!/usr/bin/env bash
# Phase 2 concurrency checks (v3). Synthetic data only (D-014).
# Usage (superuser OS account, e.g. postgres), on a FRESH database where
# phase2_roles_setup.sql and phase2_schema_draft.sql are already applied:
#   bash run_concurrency.sh <dbname> <dir_with_session_files>
# Exit 0 only if every check PASSes. Fixture failures exit 2 (never hidden).
set -u
DB="$1"; DIR="$2"
WORK="$(mktemp -d)" || exit 2
PSQL=(psql -X -q -v ON_ERROR_STOP=1 -d "$DB")
must(){ "${PSQL[@]}" -c "$1" >/dev/null || { echo "FIXTURE FAILED: ${1:0:90}"; exit 2; }; }
val(){ "${PSQL[@]}" -tAc "$1"; }
fail=0

T9=00000000-0000-0000-0000-000000000009
T10=00000000-0000-0000-0000-00000000000a
T11=00000000-0000-0000-0000-00000000000b
TPL=40000000-0000-0000-0000-000000000009

# ---- fixtures (synthetic; the owner 'postgres' is the trusted caller here) ----
must "INSERT INTO tenants (id,status) VALUES ('$T9','active'),('$T10','active'),('$T11','active');"
must "INSERT INTO students (id,tenant_id) VALUES
  ('20000000-0000-0000-0000-0000000000a1','$T9'),('20000000-0000-0000-0000-0000000000a2','$T9'),
  ('20000000-0000-0000-0000-0000000000a3','$T10'),('20000000-0000-0000-0000-0000000000a5','$T11'),
  ('20000000-0000-0000-0000-0000000000a6','$T11');"
must "INSERT INTO counselors (id,tenant_id,display_name) VALUES
  ('10000000-0000-0000-0000-0000000000a1','$T9','Synthetic Counselor T9'),
  ('10000000-0000-0000-0000-0000000000a2','$T10','Synthetic Counselor T10');"
must "INSERT INTO students (id,tenant_id,mobile_normalized,academic_grade_key) VALUES
  ('20000000-0000-0000-0000-0000000000a7','$T9','+989133333333','grade_10'),
  ('20000000-0000-0000-0000-0000000000a8','$T10','+989133333333','grade_10');"
must "INSERT INTO student_credit_accounts (tenant_id,balance) VALUES ('$T9',0),('$T10',0),('$T11',0);"
must "INSERT INTO credit_role_permissions (role_name,kind) VALUES
  ('postgres','purchase'),('postgres','activation_consume'),('postgres','refund'),
  ('postgres','cancellation_release'),('postgres','adjustment');"
must "INSERT INTO tenant_role_bindings (role_name,tenant_id) VALUES ('postgres','$T9'),('postgres','$T10'),('postgres','$T11');"
must "SELECT post_credit_transaction('$T9','purchase',1,NULL,NULL,'conc-fund-9',NULL,NULL);"
must "SELECT post_credit_transaction('$T10','purchase',1,NULL,NULL,'conc-fund-10',NULL,NULL);"
must "SELECT post_credit_transaction('$T11','purchase',1,NULL,NULL,'conc-fund-11',NULL,NULL);"
must "INSERT INTO program_templates (id,tenant_id,name) VALUES ('$TPL','$T9','Synthetic Concurrency Template');"
echo "fixtures ready: T9/T10/T11 each balance=1"

# run_session NAME SCRIPT ARGS... : runs psql in background, records its exit code.
run_session(){ local name="$1" script="$2"; shift 2
  ( psql -X -v ON_ERROR_STOP=1 -d "$DB" "$@" -f "$script" > "$WORK/$name.log" 2>&1; echo $? > "$WORK/$name.rc" ) &
}

# ---- T2-CR-04: two students race for the last credit (keys differ) ----
echo "== T2-CR-04 concurrent activation: one credit, two students =="
run_session A "$DIR/session_credit.sql" -v tenant=$T9 -v student=20000000-0000-0000-0000-0000000000a1 -v key=conc-A -v sleep_before=0 -v hold=2
run_session B "$DIR/session_credit.sql" -v tenant=$T9 -v student=20000000-0000-0000-0000-0000000000a2 -v key=conc-B -v sleep_before=0.5 -v hold=0
wait
ea=$(cat "$WORK/A.rc"); eb=$(cat "$WORK/B.rc")
bal=$(val "SELECT balance FROM student_credit_accounts WHERE tenant_id='$T9';")
cons=$(val "SELECT count(*) FROM credit_transactions WHERE tenant_id='$T9' AND kind='activation_consume';")
drift=$(val "SELECT drift FROM credit_reconciliation WHERE tenant_id='$T9';")
echo "exit A=$ea B=$eb ; balance=$bal (exp 0) ; consume_rows=$cons (exp 1) ; drift=$drift (exp 0)"
echo "B error: $(grep -m1 ERROR "$WORK/B.log" | sed 's/.*ERROR:  //' || true)"
if [ "$ea" = "0" ] && [ "$eb" = "3" ] && grep -q 'insufficient credit' "$WORK/B.log" \
   && [ "$bal" = "0" ] && [ "$cons" = "1" ] && [ "$drift" = "0" ]; then
  echo "PASS T2-CR-04"
else echo "FAIL T2-CR-04"; fail=1; fi

# ---- T2-CR-04b: identical key and identical payload from two sessions ----
echo "== T2-CR-04b concurrent identical canonical payload =="
run_session C "$DIR/session_credit.sql" -v tenant=$T10 -v student=20000000-0000-0000-0000-0000000000a3 -v key=conc-same -v sleep_before=0 -v hold=2
run_session D "$DIR/session_credit.sql" -v tenant=$T10 -v student=20000000-0000-0000-0000-0000000000a3 -v key=conc-same -v sleep_before=0.5 -v hold=0
wait
ec=$(cat "$WORK/C.rc"); ed=$(cat "$WORK/D.rc")
rows=$(val "SELECT count(*) FROM credit_transactions WHERE tenant_id='$T10' AND idempotency_key='conc-same';")
bal10=$(val "SELECT balance FROM student_credit_accounts WHERE tenant_id='$T10';")
echo "exit C=$ec D=$ed ; ledger rows=$rows (exp 1) ; balance=$bal10 (exp 0)"
if [ "$ec" = "0" ] && [ "$ed" = "0" ] && [ "$rows" = "1" ] && [ "$bal10" = "0" ]; then
  echo "PASS T2-CR-04b"; else echo "FAIL T2-CR-04b"; fail=1; fi

# ---- T2-CR-04c: identical key but DIFFERENT canonical payload (student differs) ----
echo "== T2-CR-04c concurrent same key, different canonical payload =="
run_session E "$DIR/session_credit.sql" -v tenant=$T11 -v student=20000000-0000-0000-0000-0000000000a5 -v key=conc-diff -v sleep_before=0 -v hold=2
run_session F "$DIR/session_credit.sql" -v tenant=$T11 -v student=20000000-0000-0000-0000-0000000000a6 -v key=conc-diff -v sleep_before=0.5 -v hold=0
wait
ee=$(cat "$WORK/E.rc"); ef=$(cat "$WORK/F.rc")
rows11=$(val "SELECT count(*) FROM credit_transactions WHERE tenant_id='$T11' AND idempotency_key='conc-diff';")
bal11=$(val "SELECT balance FROM student_credit_accounts WHERE tenant_id='$T11';")
echo "exit E=$ee F=$ef ; F error: $(grep -m1 ERROR "$WORK/F.log" | sed 's/.*ERROR:  //' || true)"
if [ "$ee" = "0" ] && [ "$ef" = "3" ] && grep -q 'different canonical payload' "$WORK/F.log" \
   && [ "$rows11" = "1" ] && [ "$bal11" = "0" ]; then
  echo "PASS T2-CR-04c"; else echo "FAIL T2-CR-04c"; fail=1; fi

# ---- T2-VER-02: concurrent creation of the same template version number ----
echo "== T2-VER-02 concurrent publication of the same version number =="
run_session G "$DIR/session_publish.sql" -v tenant=$T9 -v template=$TPL -v vid=50000000-0000-0000-0000-0000000000e1 -v version=1 -v sleep_before=0 -v hold=2
run_session H "$DIR/session_publish.sql" -v tenant=$T9 -v template=$TPL -v vid=50000000-0000-0000-0000-0000000000e2 -v version=1 -v sleep_before=0.5 -v hold=0
wait
eg=$(cat "$WORK/G.rc"); eh=$(cat "$WORK/H.rc")
nv=$(val "SELECT count(*) FROM program_versions WHERE program_template_id='$TPL' AND version_number=1;")
echo "exit G=$eg H=$eh ; H error: $(grep -m1 ERROR "$WORK/H.log" | sed 's/.*ERROR:  //' || true) ; rows=$nv"
if [ "$eg" = "0" ] && [ "$eh" = "3" ] && grep -q 'unique' "$WORK/H.log" && [ "$nv" = "1" ]; then
  echo "PASS T2-VER-02"; else echo "FAIL T2-VER-02"; fail=1; fi

# ---- T2-ENR-025-03: cross-tenant race for one global mobile+grade key ----
echo "== T2-ENR-025-03 concurrent cross-tenant claim of mobile+grade =="
run_session J "$DIR/session_enrollment.sql" -v tenant=$T9 -v counselor=10000000-0000-0000-0000-0000000000a1 -v student=20000000-0000-0000-0000-0000000000a7 -v enrollment=81000000-0000-0000-0000-0000000000a7 -v sleep_before=0 -v hold=2
run_session K "$DIR/session_enrollment.sql" -v tenant=$T10 -v counselor=10000000-0000-0000-0000-0000000000a2 -v student=20000000-0000-0000-0000-0000000000a8 -v enrollment=81000000-0000-0000-0000-0000000000a8 -v sleep_before=0.5 -v hold=0
wait
ej=$(cat "$WORK/J.rc"); ek=$(cat "$WORK/K.rc")
registry=$(val "SELECT count(*) FROM active_student_counselor_registry WHERE normalized_mobile='+989133333333' AND academic_grade_key='grade_10';")
active=$(val "SELECT count(*) FROM counselor_students WHERE id IN ('81000000-0000-0000-0000-0000000000a7','81000000-0000-0000-0000-0000000000a8') AND status='active';")
echo "exit J=$ej K=$ek ; registry rows=$registry (exp 1) ; active enrollments=$active (exp 1)"
echo "K error: $(grep -m1 'duplicate key value violates unique constraint' "$WORK/K.log" | sed 's/.*ERROR:  //' || true)"
if { [ "$ej" = "0" ] && [ "$ek" = "3" ] && grep -q 'active_student_counselor_registry_pkey' "$WORK/K.log" && [ "$registry" = "1" ] && [ "$active" = "1" ]; } \
   || { [ "$ek" = "0" ] && [ "$ej" = "3" ] && grep -q 'active_student_counselor_registry_pkey' "$WORK/J.log" && [ "$registry" = "1" ] && [ "$active" = "1" ]; }; then
  echo "PASS T2-ENR-025-03"
else echo "FAIL T2-ENR-025-03"; fail=1; fi

echo "== concurrency summary: $([ $fail -eq 0 ] && echo ALL_PASS || echo HAS_FAILURES) =="
rm -rf "$WORK"
exit $fail
