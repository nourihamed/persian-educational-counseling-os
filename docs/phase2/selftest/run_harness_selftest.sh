#!/usr/bin/env bash
# Controlled-fault self-tests for the Phase 2 harness. Each test works on a COPY of docs/phase2,
# injects one fault, and asserts that the harness reports it. Canonical files are never modified.
# Usage (superuser OS account): bash run_harness_selftest.sh <docs/phase2 dir> <S1|S2|S3|S4|S5>
set -u
P2="${1:?usage: run_harness_selftest.sh <docs/phase2> <S1..S5>}"; T="${2:?test id S1..S5}"
W="$(mktemp -d)"; CP="$W/phase2"; cp -r "$P2" "$CP"; chmod -R a+rwX "$W"
ok(){ echo "PASS $T: $1"; rm -rf "$W"; exit 0; }
bad(){ echo "FAIL $T: $1"; echo "(work dir kept: $W)"; exit 1; }
inject(){ # inject FILE OLD NEW : replace OLD (must occur exactly once) in the COPY
  python3 - "$1" "$2" "$3" <<'PY' || exit 9
import sys; p,o,n=sys.argv[1:4]; s=open(p,encoding='utf-8').read()
c=s.count(o); assert c==1, f'target occurs {c} times'; open(p,'w',encoding='utf-8').write(s.replace(o,n))
PY
}
case "$T" in
S1) # A failing baseline must prevent mutant evaluation.
  inject "$CP/schema/phase2_constraint_tests.sql" "'23514', 'published');  -- missing-in-tenant" "'23505', 'published');  -- missing-in-tenant"
  out=$(bash "$CP/mutation/run_mutants.sh" "$CP" 2>&1); rc=$?
  echo "$out" | grep -q "BASELINE SUITE FAILED" || bad "baseline failure not reported"
  [ "$(echo "$out" | grep -c '^DETECTED ')" -eq 0 ] || bad "mutants were evaluated despite failing baseline"
  [ $rc -ne 0 ] || bad "exit code is 0 despite failing baseline (rc=$rc)"
  ok "baseline failure reported, zero mutants evaluated, exit=$rc";;
S2) # A surviving mutant must be reported NOT DETECTED and fail the run.
  python3 - "$CP/mutation/mutants.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=s.replace('MUTANTS = [\n','MUTANTS = [\n ("NOOP-survivor", "no-op control: must survive", "IF v_existing.kind = p_kind", "IF v_existing.kind = p_kind"),\n',1)
open(p,'w',encoding='utf-8').write(s)
PY
  out=$(bash "$CP/mutation/run_mutants.sh" "$CP" 2>&1); rc=$?
  echo "$out" | grep -q "^NOT DETECTED  NOOP-survivor" || bad "surviving mutant not reported NOT DETECTED"
  [ $rc -ne 0 ] || bad "run exit 0 although a mutant survived"
  ok "surviving mutant reported NOT DETECTED, exit=$rc";;
S3) # An invalid mutant (DDL does not load) must not be counted as DETECTED, and must fail the run.
  python3 - "$CP/mutation/mutants.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=s.replace('MUTANTS = [\n','MUTANTS = [\n ("INVALID-ddl", "syntactically invalid mutant: must not count", "IF v_existing.kind = p_kind", "IF v_existing.kind = p_kind THEN THEN"),\n',1)
open(p,'w',encoding='utf-8').write(s)
PY
  out=$(bash "$CP/mutation/run_mutants.sh" "$CP" 2>&1); rc=$?
  echo "$out" | grep -q "INVALID-ddl: mutant DDL did not load" || bad "invalid mutant not reported as invalid"
  echo "$out" | grep -q "^DETECTED  INVALID-ddl" && bad "invalid mutant was counted as DETECTED"
  [ $rc -ne 0 ] || bad "run exit 0 although a mutant was invalid"
  ok "invalid mutant reported invalid, not counted as detected, exit=$rc";;
*) bad "unknown test id (S4/S5 are full-runner tests: use run_harness_selftest_full.sh)";;
esac
