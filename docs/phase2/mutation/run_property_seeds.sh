#!/usr/bin/env bash
# Multi-seed property run: 12 explicit seeds (setseed accepts only [-1,1]), each on its own synthetic
# tenant, 80 operations each. Seeds are listed in SEEDS below and reproducible by value.
# Usage (superuser OS account): bash run_property_seeds.sh <docs/phase2 dir>
set -u
P2="${1:?usage}"; S="$P2/schema"; M="$P2/mutation"
DB=p3_prop
psql -X -q -d postgres -c "DROP DATABASE IF EXISTS $DB;" -c "CREATE DATABASE $DB;" || exit 2
psql -X -v ON_ERROR_STOP=1 -q -d $DB -f "$S/phase2_roles_setup.sql" || exit 2
psql -X -v ON_ERROR_STOP=1 -q -d $DB -f "$S/phase2_schema_draft.sql" || exit 2
psql -X -v ON_ERROR_STOP=1 -q -d $DB -f "$M/property_seeded.sql" || exit 2
psql -X -v ON_ERROR_STOP=1 -q -d $DB -c "INSERT INTO credit_role_permissions (role_name,kind) VALUES
 ('postgres','purchase'),('postgres','activation_consume');" || exit 2
fail=0; n=0
SEEDS="0.11 0.22 0.33 0.44 0.55 0.66 0.77 0.88 0.12 0.23 0.34 0.45"
idx=0
for seed in $SEEDS; do
  n=$((n+1)); idx=$((idx+1))
  T=$(printf '00000000-0000-0000-0000-%012d' $((1000+idx)))
  ST=$(printf '20000000-0000-0000-0000-%012d' $((1000+idx)))
  psql -X -v ON_ERROR_STOP=1 -q -d $DB -c "INSERT INTO tenants (id,status) VALUES ('$T','active');
    INSERT INTO student_credit_accounts (tenant_id,balance) VALUES ('$T',0);
    INSERT INTO tenant_role_bindings (role_name,tenant_id) VALUES ('postgres','$T');
    INSERT INTO students (id,tenant_id) VALUES ('$ST','$T');" || { echo "seed $seed: fixture failed"; fail=1; continue; }
  out=$(psql -X -v ON_ERROR_STOP=1 -tA -d $DB -c "SELECT property_run('$T','$ST',$seed,80);" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then echo "PASS seed=$seed : $out"; else echo "FAIL seed=$seed (exit $rc): $out"; fail=1; fi
done
echo "seeds run: $n ; failures: $fail"
[ $fail -eq 0 ] && exit 0 || exit 1
