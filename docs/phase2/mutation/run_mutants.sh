#!/usr/bin/env bash
# Mutation testing for the authorization and idempotency rules of post_credit_transaction().
# Each mutant is generated in a temp dir (canonical file is never modified), loaded into its own
# disposable database, and run through the FULL constraint suite with ON_ERROR_STOP=1.
# DETECTED = the suite exits non-zero AND reports a FAIL line. NOT DETECTED = suite passed.
# Usage (superuser OS account): bash run_mutants.sh <docs/phase2 dir>
set -u
P2="${1:?usage: run_mutants.sh <docs/phase2>}"
S="$P2/schema"; M="$P2/mutation"
WORK="$(mktemp -d)" || exit 2
fails=0; total=0
python3 "$M/mutants.py" "$S/phase2_schema_draft.sql" "$WORK" > "$WORK/list.tsv" 2> "$WORK/gen.err" || { cat "$WORK/gen.err"; exit 2; }
cat "$WORK/gen.err"
while IFS=$'\t' read -r mid desc path; do
  total=$((total+1)); db="p3_m_$(echo "$mid" | tr 'A-Z-' 'a-z_')"
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $db;" -c "CREATE DATABASE $db;" >/dev/null || { echo "$mid: cannot create db"; exit 2; }
  psql -X -v ON_ERROR_STOP=1 -q -d "$db" -f "$S/phase2_roles_setup.sql" >/dev/null || exit 2
  psql -X -v ON_ERROR_STOP=1 -q -d "$db" -f "$path" >/dev/null 2>"$WORK/$mid.build.err" || { echo "$mid: mutant DDL did not load"; cat "$WORK/$mid.build.err"; exit 2; }
  psql -X -v ON_ERROR_STOP=1 -d "$db" -f "$S/phase2_constraint_tests.sql" > "$WORK/$mid.suite.log" 2>&1; rc=$?
  first=$(grep -m1 -oE 'FAIL T2-[A-Za-z0-9-]+' "$WORK/$mid.suite.log" || true)
  if [ $rc -ne 0 ] && [ -n "$first" ]; then
    echo "DETECTED  $mid  ($desc)  suite exit=$rc  first failure: $first"
  else
    echo "NOT DETECTED  $mid  ($desc)  suite exit=$rc"; fails=$((fails+1))
  fi
  psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $db;" >/dev/null
done < "$WORK/list.tsv"
echo "mutants run: $total ; not detected: $fails"
# Restoration: the canonical schema must still pass the whole suite on a fresh database.
psql -X -q -d postgres -c "DROP DATABASE IF EXISTS p3_m_restore;" -c "CREATE DATABASE p3_m_restore;" >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -d p3_m_restore -f "$S/phase2_roles_setup.sql" >/dev/null
psql -X -v ON_ERROR_STOP=1 -q -d p3_m_restore -f "$S/phase2_schema_draft.sql" >/dev/null
psql -X -v ON_ERROR_STOP=1 -d p3_m_restore -f "$S/phase2_constraint_tests.sql" > "$WORK/restore.log" 2>&1; rr=$?
echo "restoration (canonical suite) exit=$rr"
rm -rf "$WORK"
[ $fails -eq 0 ] && [ $rr -eq 0 ] && exit 0 || exit 1
