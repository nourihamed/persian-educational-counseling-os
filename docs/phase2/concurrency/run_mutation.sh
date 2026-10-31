#!/usr/bin/env bash
# P2-R04 mutation test: remove the account row lock in post_credit_transaction() and
# verify that the concurrency harness DETECTS the defect (exit != 0 and T2-CR-04 FAIL).
# The canonical schema file is never modified: the mutant is generated in a temp dir and
# loaded into its own disposable database. Exit 0 = mutation detected (test is valid).
#   bash run_mutation.sh <dir_with_schema_and_concurrency> <roles_file> <schema_file> <session_dir>
set -u
SCHEMA_DIR="$1"; ROLES="$2"; SCHEMA="$3"; SESSIONS="$4"
DB=p3_mutant
WORK="$(mktemp -d)" || exit 2
MUT="$WORK/schema_mutant.sql"
hits=$(grep -c 'WHERE tenant_id = p_tenant FOR UPDATE;' "$SCHEMA")
if [ "$hits" != "1" ]; then echo "MUTATION NOT APPLIED: expected exactly 1 lock site, found $hits"; exit 2; fi
sed 's/WHERE tenant_id = p_tenant FOR UPDATE;/WHERE tenant_id = p_tenant;  -- MUTANT: lock removed/' "$SCHEMA" > "$MUT"
echo "mutant lock sites remaining: $(grep -c 'FOR UPDATE' "$MUT")  (canonical had: $(grep -c 'FOR UPDATE' "$SCHEMA"))"
psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB;" -c "CREATE DATABASE $DB;" || exit 2
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$ROLES" || exit 2
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$MUT"   || exit 2
bash "$SCHEMA_DIR/run_concurrency.sh" "$DB" "$SESSIONS" > "$WORK/harness.log" 2>&1
rc=$?
cat "$WORK/harness.log"
if [ $rc -ne 0 ] && grep -q 'FAIL T2-CR-04$' "$WORK/harness.log"; then
  echo "MUTATION DETECTED: harness exit=$rc and T2-CR-04 FAILED on the mutant (expected)"
  rm -rf "$WORK"; exit 0
fi
echo "MUTATION NOT DETECTED: harness exit=$rc (the concurrency test is not sensitive to the lock)"
rm -rf "$WORK"; exit 1
