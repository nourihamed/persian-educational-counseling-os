#!/usr/bin/env bash
# Full reproducible Phase 2 verification on a LOCAL throwaway PostgreSQL (15+).
# Run as a superuser OS account (e.g. postgres). Synthetic data only (D-014).
#   sudo -u postgres bash docs/phase2/run_all.sh /path/to/docs/phase2 > evidence.log 2>&1; echo "exit=$?"
set -u
P2="${1:?usage: run_all.sh <path-to-docs/phase2>}"
S="$P2/schema"; C="$P2/concurrency"
rc=0
fresh(){ psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $1;" -c "CREATE DATABASE $1;" >/dev/null; }

echo "PostgreSQL: $(psql -X -tAc 'select version()' -d postgres | cut -c1-60)"
echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "=== [1] DDL + constraint suite (fresh DB p2_suite) ==="
fresh p2_suite
psql -X -v ON_ERROR_STOP=1 -q -d p2_suite -f "$S/phase2_roles_setup.sql";  echo "roles exit=$?"
psql -X -v ON_ERROR_STOP=1 -q -d p2_suite -f "$S/phase2_schema_draft.sql"; echo "schema exit=$?"
psql -X -v ON_ERROR_STOP=1 -d p2_suite -f "$S/phase2_constraint_tests.sql" > /tmp/p2_suite.log 2>&1; s=$?
echo "suite psql exit=$s"
echo "PASS notices: $(grep -c 'NOTICE:  PASS' /tmp/p2_suite.log)"
echo "FAIL lines:   $(grep -c 'FAIL' /tmp/p2_suite.log)"
[ $s -eq 0 ] || rc=1
echo "--- PASS list ---"; grep 'NOTICE:  PASS' /tmp/p2_suite.log | sed 's/.*NOTICE:  //'

echo "=== [2] Concurrency (fresh DB p2_conc) ==="
fresh p2_conc
psql -X -v ON_ERROR_STOP=1 -q -d p2_conc -f "$S/phase2_roles_setup.sql"
psql -X -v ON_ERROR_STOP=1 -q -d p2_conc -f "$S/phase2_schema_draft.sql"
bash "$C/run_concurrency.sh" p2_conc "$C" ; cc=$?
echo "concurrency exit=$cc"
[ $cc -eq 0 ] || rc=1

echo "=== RESULT: $([ $rc -eq 0 ] && echo ALL_EXECUTED_CHECKS_PASSED || echo FAILURES_PRESENT) (exit $rc) ==="
exit $rc
