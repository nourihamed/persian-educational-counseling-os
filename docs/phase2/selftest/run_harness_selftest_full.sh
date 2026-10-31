#!/usr/bin/env bash
# Full-runner controlled-fault self-tests (S4: failed concurrency stage; S5: cleanup failure).
# Each works on a COPY; canonical files are never modified. Usage: bash run_harness_selftest_full.sh <docs/phase2> <S4|S5>
set -u
P2="${1:?usage}"; T="${2:?S4|S5}"
W="$(mktemp -d)"; CP="$W/phase2"; cp -r "$P2" "$CP"; chmod -R a+rwX "$W"
inject(){ python3 - "$1" "$2" "$3" <<'PY' || exit 9
import sys; p,o,n=sys.argv[1:4]; s=open(p,encoding='utf-8').read()
c=s.count(o); assert c==1, f'target occurs {c} times'; open(p,'w',encoding='utf-8').write(s.replace(o,n))
PY
}
case "$T" in
S4) # A failing concurrency check must fail the whole run and be named.
  inject "$CP/concurrency/run_concurrency.sh" '[ "$rows" = "1" ] && [ "$bal10" = "0" ]' '[ "$rows" = "2" ] && [ "$bal10" = "0" ]'
  out=$(bash "$CP/run_all.sh" "$CP" 2>&1); rc=$?
  echo "$out" | grep -q "STAGE 2-concurrency: FAILED" || { echo "FAIL $T: failing concurrency stage not reported"; exit 1; }
  echo "$out" | grep -q "ALL_EXECUTED_CHECKS_PASSED" && { echo "FAIL $T: success summary printed despite failure"; exit 1; }
  [ $rc -ne 0 ] || { echo "FAIL $T: exit 0 despite failure"; exit 1; }
  echo "PASS $T: failing concurrency stage reported by name, no success summary, exit=$rc";;
S5) # A cleanup failure must fail the whole run and be named. A real cleanup failure is produced by
    # keeping an open session on a disposable database that the runner is told to drop.
    # NOTE: this script already runs as the postgres OS user, so psql is called directly (no su).
  BLK=p3_selftest_block
  psql -q -X -d postgres -c "DROP DATABASE IF EXISTS $BLK;" -c "CREATE DATABASE $BLK;" >/dev/null 2>&1 || { echo "FAIL $T: cannot create blocker db"; exit 1; }
  timeout 260 psql -q -X -d "$BLK" -c "select pg_sleep(250)" >/dev/null 2>&1 &
  sleep 3
  n_before=$(psql -tAX -d postgres -c "select count(*) from pg_stat_activity where datname='$BLK'")
  [ "$n_before" -ge 1 ] || { echo "FAIL $T: precondition not met: no session holds $BLK (count=$n_before)"; exit 1; }
  inject "$CP/run_all.sh" 'p3_m_h02_insert_only p3_m_baseline; do' "p3_m_h02_insert_only p3_m_baseline $BLK; do"
  out=$(bash "$CP/run_all.sh" "$CP" 2>&1); rc=$?
  printf "%s\n" "$out" > "$W/out.log"
  psql -q -X -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$BLK' AND pid<>pg_backend_pid();" >/dev/null 2>&1
  sleep 2
  psql -q -X -d postgres -c "DROP DATABASE IF EXISTS $BLK;" >/dev/null 2>&1
  echo "$out" | grep -q "CLEANUP FAILED \[drop $BLK\]" || { echo "FAIL $T: cleanup failure not reported (blocker sessions before run=$n_before)"; grep -iE "cleanup|STAGE 7|RESULT" "$W/out.log" | tail -6; echo "(raw output: $W/out.log)"; exit 1; }
  echo "$out" | grep -q "STAGE 7-cleanup: FAILED" || { echo "FAIL $T: cleanup stage not marked failed"; exit 1; }
  echo "$out" | grep -q "ALL_EXECUTED_CHECKS_PASSED" && { echo "FAIL $T: success summary despite cleanup failure"; exit 1; }
  [ $rc -ne 0 ] || { echo "FAIL $T: exit 0 despite cleanup failure"; exit 1; }
  echo "PASS $T: cleanup failure reported by name, stage 7 failed, no success summary, exit=$rc (blocker sessions before run=$n_before)";;
*) echo "unknown test"; exit 2;;
esac
rm -rf "$W"
