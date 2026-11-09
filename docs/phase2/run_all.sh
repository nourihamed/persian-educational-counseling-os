#!/usr/bin/env bash
# Full reproducible Phase 2 verification (v5) on a LOCAL throwaway PostgreSQL 15+.
# Synthetic data only (D-014). Run as a superuser OS account (e.g. postgres).
#   sudo -u postgres bash docs/phase2/run_all.sh docs/phase2 > run.log 2>&1; echo "exit=$?"
#
# Exit status: 0 only if EVERY required stage passed and cleanup succeeded.
# Stages that depend on an earlier failed stage are reported as SKIPPED and make the run fail.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
P2="${1:?usage: run_all.sh <path-to-docs/phase2>}"
. "$HERE/verify_lib.sh"
S="$P2/schema"; C="$P2/concurrency"; MU="$P2/mutation"
WORK="$(mktemp -d)" || { echo "mktemp failed"; exit 2; }
FAILS=()
mark(){ if [ "$2" -eq 0 ]; then echo "STAGE $1: OK"; else echo "STAGE $1: FAILED exit=$2 class=$(classify "$2")"; FAILS+=("$1"); fi; return "$2"; }
skip(){ echo "STAGE $1: SKIPPED (prerequisite failed)"; FAILS+=("$1"); }
sha(){ sha256sum "$1" | cut -d' ' -f1; }
CREATED_DBS=(p3_suite p3_conc p3_restore p3_prop p3_mutant p3_m_restore)

echo "PostgreSQL: $(psql -X -tAc 'select version()' -d postgres 2>/dev/null | cut -c1-60)"
echo "Date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ! psql -X -q -d postgres -c 'select 1' >/dev/null 2>&1; then
  echo "STAGE 0 environment: FAILED - cannot connect to PostgreSQL (class=ENVIRONMENT)"
  FAILS+=("0-environment")
else
  before_sha=$(sha "$S/phase2_schema_draft.sql")
  echo "canonical schema sha256 (before): $before_sha"

  echo "=== [1] Roles + DDL + constraint/authorization suite (fresh DB p3_suite) ==="
  if db_fresh p3_suite && req "roles:p3_suite" psql -X -v ON_ERROR_STOP=1 -q -d p3_suite -f "$S/phase2_roles_setup.sql" && req "ddl:p3_suite" psql -X -v ON_ERROR_STOP=1 -q -d p3_suite -f "$S/phase2_schema_draft.sql"; then
    psql -X -v ON_ERROR_STOP=1 -d p3_suite -f "$S/phase2_constraint_tests.sql" > "$WORK/p3_suite.log" 2>&1; s=$?
    echo "suite psql exit=$s"
    tot=$(grep -c 'NOTICE:  PASS' "$WORK/p3_suite.log"); fix=$(grep -c 'NOTICE:  PASS fixture' "$WORK/p3_suite.log")
    echo "PASS notices (all): $tot ; fixture acceptance: $fix ; test cases (all minus fixture): $((tot-fix))"
    echo "FAIL lines: $(grep -c 'ERROR:  FAIL' "$WORK/p3_suite.log")"
    echo "--- suite log (unedited) ---"; cat "$WORK/p3_suite.log"
    mark "1-suite" $s
  else
    skip "1-suite"
  fi

  echo "=== [2] Concurrency, canonical schema (fresh DB p3_conc) ==="
  if db_fresh p3_conc && req "roles:p3_conc" psql -X -v ON_ERROR_STOP=1 -q -d p3_conc -f "$S/phase2_roles_setup.sql" && req "ddl:p3_conc" psql -X -v ON_ERROR_STOP=1 -q -d p3_conc -f "$S/phase2_schema_draft.sql"; then
    bash "$C/run_concurrency.sh" p3_conc "$C"; cc=$?
    mark "2-concurrency" $cc
  else skip "2-concurrency"; fi

  echo "=== [3] Lock-removal mutant must be DETECTED (disposable DB p3_mutant) ==="
  bash "$C/run_mutation.sh" "$C" "$S/phase2_roles_setup.sql" "$S/phase2_schema_draft.sql" "$C"; mm=$?
  mark "3-lock-mutation" $mm

  echo "=== [4] Restoration: canonical schema unchanged and passes again (fresh DB p3_restore) ==="
  after_sha=$(sha "$S/phase2_schema_draft.sql")
  echo "canonical schema sha256 (after):  $after_sha"
  if [ "$before_sha" != "$after_sha" ]; then echo "CANONICAL SCHEMA CHANGED"; FAILS+=("4-schema-changed"); fi
  if db_fresh p3_restore && req "roles:p3_restore" psql -X -v ON_ERROR_STOP=1 -q -d p3_restore -f "$S/phase2_roles_setup.sql" && req "ddl:p3_restore" psql -X -v ON_ERROR_STOP=1 -q -d p3_restore -f "$S/phase2_schema_draft.sql"; then
    bash "$C/run_concurrency.sh" p3_restore "$C" > "$WORK/p3_restore.log" 2>&1; rr=$?
    echo "restored concurrency exit=$rr"; tail -1 "$WORK/p3_restore.log"
    mark "4-restoration" $rr
  else skip "4-restoration"; fi

  echo "=== [5] Authorization and idempotency mutants (each must be DETECTED; canonical must restore) ==="
  bash "$MU/run_mutants.sh" "$P2"; mu=$?
  mark "5-auth-idem-mutants" $mu

  echo "=== [6] Property test under explicit seeds (fresh DB p3_prop) ==="
  bash "$MU/run_property_seeds.sh" "$P2"; pp=$?
  mark "6-property-seeds" $pp
fi

echo "=== [7] Cleanup: drop only the databases this run creates ==="
cleanup_fail=0
for d in "${CREATED_DBS[@]}" p3_m_auth_1 p3_m_auth_2 p3_m_auth_3 p3_m_auth_4 p3_m_idem_kind p3_m_idem_amount p3_m_idem_student p3_m_idem_order p3_m_idem_actor p3_m_idem_reason p3_m_h02_insert_only p3_m_baseline; do
  db_drop "$d" || cleanup_fail=$((cleanup_fail+1))
done
if [ $cleanup_fail -eq 0 ]; then echo "STAGE 7-cleanup: OK"; else echo "STAGE 7-cleanup: FAILED ($cleanup_fail database(s) not dropped)"; FAILS+=("7-cleanup"); fi

rm -rf "$WORK"
if [ ${#FAILS[@]} -eq 0 ]; then
  echo "=== RESULT: ALL_EXECUTED_CHECKS_PASSED (exit 0) ==="; exit 0
else
  echo "=== RESULT: FAILURES_PRESENT (exit 1) failed/skipped stages: ${FAILS[*]} ==="; exit 1
fi
