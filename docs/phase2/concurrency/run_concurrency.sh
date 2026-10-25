#!/usr/bin/env bash
# Phase 2 concurrency tests (T2-CR-03b, T2-CR-04, T2-CR-04b, T2-VER-02).
# Usage (as the postgres OS user, on a FRESH database with roles+schema already applied):
#   bash run_concurrency.sh <dbname> <dir_containing_session_files>
set -u
DB="$1"; DIR="$2"; PSQL="psql -X -q -v ON_ERROR_STOP=1 -d $DB"
T9=00000000-0000-0000-0000-000000000009
T10=00000000-0000-0000-0000-00000000000a
TPL=40000000-0000-0000-0000-000000000009
fail=0
say(){ echo "$1"; }

# ---- fixtures (synthetic) ----
$PSQL -c "INSERT INTO tenants (id,status) VALUES ('$T9','active'),('$T10','active');" >/dev/null
$PSQL -c "INSERT INTO students (id,tenant_id) VALUES
  ('20000000-0000-0000-0000-0000000000a1','$T9'),('20000000-0000-0000-0000-0000000000a2','$T9'),
  ('20000000-0000-0000-0000-0000000000a3','$T10'),('20000000-0000-0000-0000-0000000000a4','$T10');" >/dev/null
$PSQL -c "INSERT INTO student_credit_accounts (tenant_id,balance) VALUES ('$T9',0),('$T10',0);" >/dev/null
$PSQL -c "SELECT post_credit_transaction('$T9','purchase',1,NULL,NULL,'conc-fund-9',NULL,NULL);" >/dev/null
$PSQL -c "SELECT post_credit_transaction('$T10','purchase',1,NULL,NULL,'conc-fund-10',NULL,NULL);" >/dev/null
$PSQL -c "INSERT INTO program_templates (id,tenant_id,name) VALUES ('$TPL','$T9','Synthetic Concurrency Template');" >/dev/null
echo "fixtures ready: T9 balance=1 (2 contenders), T10 balance=1 (idempotency race)"

# ---- T2-CR-04: two different students race for the last credit ----
echo "== T2-CR-04 concurrent activation, one credit, two students =="
psql -X -v ON_ERROR_STOP=1 -d $DB -v tenant=$T9 -v student=20000000-0000-0000-0000-0000000000a1 -v key=conc-A -v sleep_before=0 -v hold=2 -f $DIR/session_credit.sql > /tmp/cA.log 2>&1 & pa=$!
psql -X -v ON_ERROR_STOP=1 -d $DB -v tenant=$T9 -v student=20000000-0000-0000-0000-0000000000a2 -v key=conc-B -v sleep_before=0.5 -v hold=0 -f $DIR/session_credit.sql > /tmp/cB.log 2>&1 & pb=$!
wait $pa; ea=$?; wait $pb; eb=$?
echo "session A exit=$ea ; session B exit=$eb"
echo "session B message: $(grep -m1 'ERROR' /tmp/cB.log || echo none)"
succ=0; [ $ea -eq 0 ] && succ=$((succ+1)); [ $eb -eq 0 ] && succ=$((succ+1))
bal=$($PSQL -tAc "SELECT balance FROM student_credit_accounts WHERE tenant_id='$T9';")
cons=$($PSQL -tAc "SELECT count(*) FROM credit_transactions WHERE tenant_id='$T9' AND kind='activation_consume';")
drift=$($PSQL -tAc "SELECT drift FROM credit_reconciliation WHERE tenant_id='$T9';")
echo "successes=$succ (expected 1) balance=$bal (expected 0) consume_rows=$cons (expected 1) drift=$drift (expected 0)"
if [ $succ -eq 1 ] && [ "$bal" = "0" ] && [ "$cons" = "1" ] && [ "$drift" = "0" ] && [ $eb -eq 3 ]; then
  echo "PASS T2-CR-04"; else echo "FAIL T2-CR-04"; fail=1; fi

# ---- T2-CR-04b: same idempotency key from two sessions on a 1-credit tenant ----
echo "== T2-CR-04b concurrent identical idempotency key =="
psql -X -v ON_ERROR_STOP=1 -d $DB -v tenant=$T10 -v student=20000000-0000-0000-0000-0000000000a3 -v key=conc-same -v sleep_before=0 -v hold=2 -f $DIR/session_credit.sql > /tmp/cC.log 2>&1 & pc=$!
psql -X -v ON_ERROR_STOP=1 -d $DB -v tenant=$T10 -v student=20000000-0000-0000-0000-0000000000a3 -v key=conc-same -v sleep_before=0.5 -v hold=0 -f $DIR/session_credit.sql > /tmp/cD.log 2>&1 & pd=$!
wait $pc; ec=$?; wait $pd; ed=$?
rows=$($PSQL -tAc "SELECT count(*) FROM credit_transactions WHERE tenant_id='$T10' AND idempotency_key='conc-same';")
bal10=$($PSQL -tAc "SELECT balance FROM student_credit_accounts WHERE tenant_id='$T10';")
echo "exit C=$ec D=$ed ; ledger rows for key=$rows (expected 1) ; balance=$bal10 (expected 0)"
if [ $ec -eq 0 ] && [ $ed -eq 0 ] && [ "$rows" = "1" ] && [ "$bal10" = "0" ]; then
  echo "PASS T2-CR-04b"; else echo "FAIL T2-CR-04b"; fail=1; fi

# ---- T2-VER-02: two sessions create the same template version number concurrently ----
echo "== T2-VER-02 concurrent publication of the same version number =="
psql -X -v ON_ERROR_STOP=1 -d $DB -v tenant=$T9 -v template=$TPL -v vid=50000000-0000-0000-0000-0000000000e1 -v version=1 -v sleep_before=0 -v hold=2 -f $DIR/session_publish.sql > /tmp/vE.log 2>&1 & pe=$!
psql -X -v ON_ERROR_STOP=1 -d $DB -v tenant=$T9 -v template=$TPL -v vid=50000000-0000-0000-0000-0000000000e2 -v version=1 -v sleep_before=0.5 -v hold=0 -f $DIR/session_publish.sql > /tmp/vF.log 2>&1 & pf=$!
wait $pe; ee=$?; wait $pf; ef=$?
echo "exit E=$ee F=$ef ; F message: $(grep -m1 'ERROR' /tmp/vF.log || echo none)"
nv=$($PSQL -tAc "SELECT count(*) FROM program_versions WHERE program_template_id='$TPL' AND version_number=1;")
if [ $ee -eq 0 ] && [ $ef -eq 3 ] && [ "$nv" = "1" ] && grep -q 'unique' /tmp/vF.log; then
  echo "PASS T2-VER-02 (one winner, loser rejected by unique constraint, rows=$nv)"; else echo "FAIL T2-VER-02"; fail=1; fi

echo "== concurrency summary: $([ $fail -eq 0 ] && echo ALL_PASS || echo HAS_FAILURES) =="
exit $fail
