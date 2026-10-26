#!/usr/bin/env bash
# Full reproducible Phase 2 verification (v3) on a LOCAL throwaway PostgreSQL 15+.
# Synthetic data only (D-014). Run as a superuser OS account (e.g. postgres).
#   sudo -u postgres bash docs/phase2/run_all.sh docs/phase2 > run.log 2>&1; echo "exit=$?"
set -u
P2="${1:?usage: run_all.sh <path-to-docs/phase2>}"
S="$P2/schema"; C="$P2/concurrency"
rc=0
fresh(){ psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $1;" -c "CREATE DATABASE $1;" >/dev/null || { echo "cannot create $1"; exit 2; }; }
sha(){ sha256sum "$1" | cut -d' ' -f1; }

echo "PostgreSQL: $(psql -X -tAc 'select version()' -d postgres | cut -c1-60)"
echo "Date (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
before_sha=$(sha "$S/phase2_schema_draft.sql")
echo "canonical schema sha256 (before): $before_sha"

echo "=== [1] Roles + DDL + constraint/authorization suite (fresh DB p3_suite) ==="
fresh p3_suite
psql -X -v ON_ERROR_STOP=1 -q -d p3_suite -f "$S/phase2_roles_setup.sql";  echo "roles exit=$?"
psql -X -v ON_ERROR_STOP=1 -q -d p3_suite -f "$S/phase2_schema_draft.sql"; echo "schema exit=$?"
psql -X -v ON_ERROR_STOP=1 -d p3_suite -f "$S/phase2_constraint_tests.sql" > /tmp/p3_suite.log 2>&1; s=$?
echo "suite psql exit=$s"
echo "PASS notices: $(grep -c 'NOTICE:  PASS' /tmp/p3_suite.log)"
echo "FAIL lines:   $(grep -c 'FAIL' /tmp/p3_suite.log)"
[ $s -eq 0 ] || rc=1
echo "--- suite log (unedited) ---"; cat /tmp/p3_suite.log

echo "=== [2] Concurrency, canonical schema (fresh DB p3_conc) ==="
fresh p3_conc
psql -X -v ON_ERROR_STOP=1 -q -d p3_conc -f "$S/phase2_roles_setup.sql"
psql -X -v ON_ERROR_STOP=1 -q -d p3_conc -f "$S/phase2_schema_draft.sql"
bash "$C/run_concurrency.sh" p3_conc "$C"; cc=$?
echo "concurrency exit=$cc"
[ $cc -eq 0 ] || rc=1

echo "=== [3] Mutation test: lock removed must be DETECTED (disposable DB p3_mutant) ==="
bash "$C/run_mutation.sh" "$C" "$S/phase2_roles_setup.sql" "$S/phase2_schema_draft.sql" "$C"; mm=$?
echo "mutation exit=$mm  (0 = mutation detected, i.e. the test is sensitive)"
[ $mm -eq 0 ] || rc=1

echo "=== [4] Restoration: canonical schema untouched and passes again (fresh DB p3_restore) ==="
after_sha=$(sha "$S/phase2_schema_draft.sql")
echo "canonical schema sha256 (after):  $after_sha"
[ "$before_sha" = "$after_sha" ] || { echo "CANONICAL SCHEMA CHANGED"; rc=1; }
fresh p3_restore
psql -X -v ON_ERROR_STOP=1 -q -d p3_restore -f "$S/phase2_roles_setup.sql"
psql -X -v ON_ERROR_STOP=1 -q -d p3_restore -f "$S/phase2_schema_draft.sql"
bash "$C/run_concurrency.sh" p3_restore "$C" > /tmp/p3_restore.log 2>&1; rr=$?
echo "restored concurrency exit=$rr"; tail -1 /tmp/p3_restore.log
[ $rr -eq 0 ] || rc=1

echo "=== RESULT: $([ $rc -eq 0 ] && echo ALL_EXECUTED_CHECKS_PASSED || echo FAILURES_PRESENT) (exit $rc) ==="
exit $rc
