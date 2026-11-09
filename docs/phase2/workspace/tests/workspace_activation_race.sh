#!/usr/bin/env bash
# Two concurrent activation commands for one enrollment must yield one activation/debit/capacity event.
# Usage: bash workspace_activation_race.sh <fresh-db-name>
set -u
DB="${1:?database name required}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL'
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a9100000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,role_key,status)
VALUES('b9100000-0000-0000-0000-000000000001','c9100000-0000-0000-0000-000000000001','counselor','active');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES('e9100000-0000-0000-0000-000000000001','f9100000-0000-0000-0000-000000000001','Race Student','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state)
VALUES('a9200000-0000-0000-0000-000000000001','e9100000-0000-0000-0000-000000000001',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES('b9200000-0000-0000-0000-000000000001','a9200000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001',true,'active',now());
INSERT INTO credit_wallets(wallet_id,currency_code)
VALUES('c9200000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES('d9200000-0000-0000-0000-000000000001','c9200000-0000-0000-0000-000000000001','grant',10,'race-opening-grant','synthetic race opening balance');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value)
VALUES('active_students',0,2);
SQL
if [ "$?" -ne 0 ]; then echo "FAIL WS-ACT-RACE fixture setup"; exit 2; fi

cat > "$W/a.sql" <<'SQL'
BEGIN;
SELECT activate_student_enrollment(
  'race-activation-a','a9200000-0000-0000-0000-000000000001',
  'c9200000-0000-0000-0000-000000000001',1,8,
  'b9100000-0000-0000-0000-000000000001');
SELECT pg_sleep(2);
COMMIT;
SQL

cat > "$W/b.sql" <<'SQL'
SELECT pg_sleep(0.4);
BEGIN;
SELECT activate_student_enrollment(
  'race-activation-b','a9200000-0000-0000-0000-000000000001',
  'c9200000-0000-0000-0000-000000000001',1,8,
  'b9100000-0000-0000-0000-000000000001');
COMMIT;
SQL

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a.sql" >"$W/a.log" 2>&1 & pa=$!
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!
wait "$pa"; ea=$?
wait "$pb"; eb=$?

state="$(psql -X -tA -d "$DB" -c "SELECT state FROM enrollments WHERE enrollment_id='a9200000-0000-0000-0000-000000000001'")"
balance="$(psql -X -tA -d "$DB" -c "SELECT COALESCE(sum(amount),0) FROM credit_transactions WHERE wallet_id='c9200000-0000-0000-0000-000000000001'")"
debits="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM credit_transactions WHERE wallet_id='c9200000-0000-0000-0000-000000000001' AND transaction_kind='activation_debit'")"
capacity="$(psql -X -tA -d "$DB" -c "SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students'")"
commands="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM activation_command_log")"

echo "exit A=$ea B=$eb; enrollment=$state; balance=$balance; debits=$debits; capacity=$capacity; commands=$commands"
echo "B error: $(grep -m1 'ERROR:' "$W/b.log" | sed 's/.*ERROR:  //')"
if [ "$ea" -eq 0 ] && [ "$eb" -eq 3 ] && [ "$state" = "active" ] \
   && [ "$balance" = "2" ] && [ "$debits" = "1" ] \
   && [ "$capacity" = "1" ] && [ "$commands" = "1" ] \
   && grep -q 'cannot be activated' "$W/b.log"; then
  echo "PASS WS-ACT-RACE-01 exactly one activation/debit/capacity reservation"
  exit 0
fi

echo "FAIL WS-ACT-RACE-01"
echo "--- session A ---"; cat "$W/a.log"
echo "--- session B ---"; cat "$W/b.log"
exit 1
