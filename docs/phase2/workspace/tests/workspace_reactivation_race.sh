#!/usr/bin/env bash
# Two concurrent reactivations of the SAME archived student on ONE reserved entitlement.
# Exactly one must succeed: one capacity slot, one command-log row, one re-consumption of the credit.
# Coordination is deterministic (no timing sleeps): the loser is made to block on the student row lock that
# reactivate_student_enrollment takes first, and the driver waits until that block is observable in
# pg_stat_activity before the winner runs.
# Usage: bash workspace_reactivation_race.sh <fresh-db-name>
set -u
DB="${1:?database name required}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL'
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'af100000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status)
VALUES('bf100000-0000-0000-0000-000000000001','cf100000-0000-0000-0000-000000000001','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES('bf100000-0000-0000-0000-000000000001','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES('df100000-0000-0000-0000-000000000001','ef100000-0000-0000-0000-000000000001','Reactivation Race','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state)
VALUES('af200000-0000-0000-0000-000000000001','df100000-0000-0000-0000-000000000001',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES(gen_random_uuid(),'af200000-0000-0000-0000-000000000001','bf100000-0000-0000-0000-000000000001',true,'active',now());
INSERT INTO credit_wallets(wallet_id,unit_code) VALUES('cf200000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'cf200000-0000-0000-0000-000000000001','grant',50,'reactivation-race-opening','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value) VALUES('active_students',0,5);
SELECT activate_student_enrollment('rr-act','af200000-0000-0000-0000-000000000001',
  'cf200000-0000-0000-0000-000000000001',1,5,'bf100000-0000-0000-0000-000000000001','2099-01-01 00:00:00+00'::timestamptz);
SELECT archive_student_enrollment('rr-arc','af200000-0000-0000-0000-000000000001',1,
  'bf100000-0000-0000-0000-000000000001','race fixture');
SQL
if [ "$?" -ne 0 ]; then echo "FAIL WS-REACT-RACE fixture setup"; exit 2; fi

reserved="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM student_entitlements WHERE state='reserved'")"
if [ "$reserved" != "1" ]; then echo "FAIL WS-REACT-RACE fixture: reserved=$reserved"; exit 2; fi

# Blocker: holds the student row so that any reactivation of this student must wait.
cat > "$W/block.sql" <<'SQL'
BEGIN;
SELECT lifecycle_state FROM students WHERE student_id='df100000-0000-0000-0000-000000000001' FOR UPDATE;
SELECT pg_sleep(30);   -- released early by the driver; only an upper bound, not a race window
COMMIT;
SQL
psql -X -q -d "$DB" -f "$W/block.sql" >"$W/block.log" 2>&1 & pblock=$!

# Wait until the blocker actually holds the row lock.
held=0
for _ in $(seq 1 100); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid=l.relation WHERE c.relname='students' AND l.mode='RowShareLock' AND l.granted")"
  if [ "$n" -ge 1 ]; then held=1; break; fi
done
if [ "$held" != "1" ]; then echo "FAIL WS-REACT-RACE blocker never took the lock"; kill "$pblock" 2>/dev/null; exit 2; fi

cat > "$W/b.sql" <<'SQL'
SELECT reactivate_student_enrollment('rr-react-b','df100000-0000-0000-0000-000000000001',
  'af300000-0000-0000-0000-00000000000b',1,'bf100000-0000-0000-0000-000000000001','bf100000-0000-0000-0000-000000000001');
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!

# Wait until B is demonstrably blocked on a lock, then release the blocker and let A run.
blocked=0
for _ in $(seq 1 200); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%reactivate_student_enrollment%'")"
  if [ "$n" -ge 1 ]; then blocked=1; break; fi
done
if [ "$blocked" != "1" ]; then echo "FAIL WS-REACT-RACE loser never blocked"; kill "$pblock" "$pb" 2>/dev/null; exit 2; fi

psql -X -tA -d "$DB" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=current_database() AND query LIKE '%pg_sleep(30)%' AND pid<>pg_backend_pid()" >/dev/null
wait "$pblock" 2>/dev/null

# A runs after the blocker is gone; B is already queued on the same student row.
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c "SELECT reactivate_student_enrollment('rr-react-a','df100000-0000-0000-0000-000000000001','af300000-0000-0000-0000-00000000000a',1,'bf100000-0000-0000-0000-000000000001','bf100000-0000-0000-0000-000000000001')" >"$W/a.log" 2>&1
ea=$?
wait "$pb"; eb=$?

logs="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM reactivation_command_log")"
events="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM capacity_events WHERE idempotency_key LIKE 'reactivation:%'")"
capacity="$(psql -X -tA -d "$DB" -c "SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students'")"
active="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM enrollments WHERE state='active'")"
consumed="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM student_entitlements WHERE state='consumed' AND reconsumed_at IS NOT NULL")"
ledger="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM credit_transactions")"
loser="$( (grep -m1 'ERROR:' "$W/a.log" "$W/b.log" 2>/dev/null || true) | sed 's/.*ERROR:  //')"

echo "exit A=$ea B=$eb; command_logs=$logs; capacity_events=$events; capacity=$capacity; active=$active; reconsumed=$consumed; ledger_rows=$ledger"
echo "loser error: $loser"

ok=1
[ "$logs" = "1" ] || { echo "FAIL WS-REACT-RACE-01 expected exactly one reactivation command"; ok=0; }
[ "$events" = "1" ] || { echo "FAIL WS-REACT-RACE-01 expected exactly one capacity reservation"; ok=0; }
[ "$capacity" = "1" ] || { echo "FAIL WS-REACT-RACE-01 expected capacity 1"; ok=0; }
[ "$active" = "1" ] || { echo "FAIL WS-REACT-RACE-01 expected exactly one active enrollment"; ok=0; }
[ "$consumed" = "1" ] || { echo "FAIL WS-REACT-RACE-01 expected the credit to be re-consumed exactly once"; ok=0; }
[ "$ledger" = "3" ] || { echo "FAIL WS-REACT-RACE-01 ledger changed (expected grant+debit+reversal)"; ok=0; }
if [ "$ea" -eq 0 ] && [ "$eb" -eq 0 ]; then echo "FAIL WS-REACT-RACE-01 both reactivations succeeded"; ok=0; fi
if [ "$ea" -ne 0 ] && [ "$eb" -ne 0 ]; then echo "FAIL WS-REACT-RACE-01 neither reactivation succeeded"; ok=0; fi

if [ "$ok" = "1" ]; then
  echo "PASS WS-REACT-RACE-01 one reserved entitlement produced exactly one reactivation under contention"
  exit 0
fi
exit 1
