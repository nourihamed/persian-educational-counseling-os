#!/usr/bin/env bash
# Two different enrollments race for the final active-student capacity slot.
# Exactly one activation/debit/reservation/audit must commit.
# Usage: bash workspace_capacity_last_slot_race.sh <fresh-db-name>
set -u
DB="${1:?database name required}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL'
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'aa100000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,role_key,status)
VALUES('bb100000-0000-0000-0000-000000000001','cc100000-0000-0000-0000-000000000001','counselor','active');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('dd100000-0000-0000-0000-000000000001','ee100000-0000-0000-0000-000000000001','Capacity Race A','grade_10','active'),
 ('dd100000-0000-0000-0000-000000000002','ee100000-0000-0000-0000-000000000002','Capacity Race B','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('aa200000-0000-0000-0000-000000000001','dd100000-0000-0000-0000-000000000001',1,'requested'),
 ('aa200000-0000-0000-0000-000000000002','dd100000-0000-0000-0000-000000000002',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES
 ('bb200000-0000-0000-0000-000000000001','aa200000-0000-0000-0000-000000000001','bb100000-0000-0000-0000-000000000001',true,'active',now()),
 ('bb200000-0000-0000-0000-000000000002','aa200000-0000-0000-0000-000000000002','bb100000-0000-0000-0000-000000000001',true,'active',now());
INSERT INTO credit_wallets(wallet_id,unit_code)
VALUES('cc200000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES('dd200000-0000-0000-0000-000000000001','cc200000-0000-0000-0000-000000000001','grant',10,'capacity-race-opening','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value)
VALUES('active_students',0,1);
SQL
if [ "$?" -ne 0 ]; then echo "FAIL WS-CAP-RACE fixture setup"; exit 2; fi

cat > "$W/a.sql" <<'SQL'
BEGIN;
SELECT activate_student_enrollment(
 'capacity-race-a','aa200000-0000-0000-0000-000000000001',
 'cc200000-0000-0000-0000-000000000001',1,8,
 'bb100000-0000-0000-0000-000000000001');
SELECT pg_sleep(1.5);
COMMIT;
SQL
cat > "$W/b.sql" <<'SQL'
SELECT pg_sleep(0.2);
BEGIN;
SELECT activate_student_enrollment(
 'capacity-race-b','aa200000-0000-0000-0000-000000000002',
 'cc200000-0000-0000-0000-000000000001',1,8,
 'bb100000-0000-0000-0000-000000000001');
COMMIT;
SQL

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a.sql" >"$W/a.log" 2>&1 & pa=$!
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!
wait "$pa"; ea=$?
wait "$pb"; eb=$?

active="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM enrollments WHERE state='active'")"
requested="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM enrollments WHERE state='requested'")"
balance="$(psql -X -tA -d "$DB" -c "SELECT COALESCE(sum(amount),0) FROM credit_transactions WHERE wallet_id='cc200000-0000-0000-0000-000000000001'")"
debits="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM credit_transactions WHERE transaction_kind='activation_debit'")"
capacity="$(psql -X -tA -d "$DB" -c "SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students'")"
commands="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM activation_command_log")"
audits="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM audit_events WHERE event_type='student.activation'")"

echo "exit A=$ea B=$eb; active=$active; requested=$requested; balance=$balance; debits=$debits; capacity=$capacity; commands=$commands; audits=$audits"
echo "B error: $(grep -m1 'ERROR:' "$W/b.log" | sed 's/.*ERROR:  //')"

if [ "$ea" -eq 0 ] && [ "$eb" -eq 3 ] && [ "$active" = "1" ] \
   && [ "$requested" = "1" ] && [ "$balance" = "2" ] && [ "$debits" = "1" ] \
   && [ "$capacity" = "1" ] && [ "$commands" = "1" ] && [ "$audits" = "1" ] \
   && grep -q 'capacity unavailable' "$W/b.log"; then
  echo "PASS WS-CAP-RACE-01 exactly one enrollment wins the final active-student slot"
  exit 0
fi

echo "FAIL WS-CAP-RACE-01"
echo "--- session A ---"; cat "$W/a.log"
echo "--- session B ---"; cat "$W/b.log"
exit 1
