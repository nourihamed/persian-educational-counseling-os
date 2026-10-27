#!/usr/bin/env bash
# Mutation testing for authorization and idempotency rules of post_credit_transaction().
# Each mutant is generated in a temp dir (canonical file is never modified), loaded into its own
# disposable database, and run through the FULL constraint suite with ON_ERROR_STOP=1.
# DETECTED = suite exits non-zero AND reports a FAIL line.  NOT DETECTED = suite passed.
# Exit 0 only if: every defined mutant was generated, every mutant was DETECTED, and the canonical
# suite passes again on a fresh database.   Usage: bash run_mutants.sh <docs/phase2 dir>
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../verify_lib.sh"
P2="${1:?usage: run_mutants.sh <docs/phase2>}"
S="$P2/schema"; M="$P2/mutation"
WORK="$(mktemp -d)" || exit 2
fails=0; total=0
python3 "$M/mutants.py" "$S/phase2_schema_draft.sql" "$WORK" > "$WORK/list.tsv" 2> "$WORK/gen.err"; gen=$?
cat "$WORK/gen.err"
if [ $gen -ne 0 ]; then echo "MUTANT GENERATION FAILED (exit $gen)"; rm -rf "$WORK"; exit 1; fi
while IFS=$'\t' read -r mid desc path; do
  total=$((total+1)); db="p3_m_$(echo "$mid" | tr 'A-Z-' 'a-z_')"
  db_fresh "$db" || { echo "$mid: cannot create database (environment)"; rm -rf "$WORK"; exit 2; }
  req "roles:$db" psql -X -v ON_ERROR_STOP=1 -q -d "$db" -f "$S/phase2_roles_setup.sql" >/dev/null || { rm -rf "$WORK"; exit 2; }
  if ! psql -X -v ON_ERROR_STOP=1 -q -d "$db" -f "$path" >/dev/null 2>"$WORK/$mid.build.err"; then
    echo "$mid: mutant DDL did not load (not a valid mutant)"; cat "$WORK/$mid.build.err"; fails=$((fails+1)); continue
  fi
  psql -X -v ON_ERROR_STOP=1 -d "$db" -f "$S/phase2_constraint_tests.sql" > "$WORK/$mid.suite.log" 2>&1; rc=$?
  first=$(grep -m1 -oE 'FAIL T2-[A-Za-z0-9-]+' "$WORK/$mid.suite.log" || true)
  if [ $rc -ne 0 ] && [ -n "$first" ]; then
    echo "DETECTED  $mid  ($desc)  suite exit=$rc  first failure: $first"
  else
    echo "NOT DETECTED  $mid  ($desc)  suite exit=$rc"; fails=$((fails+1))
  fi
  db_drop "$db" || fails=$((fails+1))
done < "$WORK/list.tsv"
echo "mutants run: $total ; not detected or invalid: $fails"
[ "$total" -gt 0 ] || { echo "NO MUTANTS RAN"; fails=$((fails+1)); }

# Restoration: canonical suite must pass on a fresh database.
db_fresh p3_m_restore || { rm -rf "$WORK"; exit 2; }
req "roles:p3_m_restore" psql -X -v ON_ERROR_STOP=1 -q -d p3_m_restore -f "$S/phase2_roles_setup.sql" >/dev/null || { rm -rf "$WORK"; exit 2; }
req "ddl:p3_m_restore" psql -X -v ON_ERROR_STOP=1 -q -d p3_m_restore -f "$S/phase2_schema_draft.sql" >/dev/null || { rm -rf "$WORK"; exit 2; }
psql -X -v ON_ERROR_STOP=1 -d p3_m_restore -f "$S/phase2_constraint_tests.sql" > "$WORK/restore.log" 2>&1; rr=$?
echo "restoration (canonical suite) exit=$rr  class=$(classify $rr)"
db_drop p3_m_restore || fails=$((fails+1))
rm -rf "$WORK"
[ $fails -eq 0 ] && [ $rr -eq 0 ] && exit 0 || exit 1
