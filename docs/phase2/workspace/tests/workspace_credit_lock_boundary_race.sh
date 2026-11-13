#!/usr/bin/env bash
# H-01 regression: the credit reversal window must be decided from a wall clock read AFTER the entitlement
# row lock is acquired, not before. A command that waits on the lock for longer than the remaining window
# must see the window as CLOSED.
#
# Coordination is deterministic, not a timing race: a blocker transaction holds the entitlement row for a
# fixed interval, the driver waits until the archive command is observably blocked on that row, and only
# then releases it. The window lengths are chosen so the outcome is unambiguous:
#   case A: 2 seconds of window left, blocked for ~8 seconds  -> window CLOSED, no credit returned
#   case B: 1 hour of window left,    blocked for ~8 seconds  -> window OPEN,   credit returned
# Case B is the control: it proves the test is not simply always refusing to return credit.
#
# Synthetic only (D-014). Usage: bash workspace_credit_lock_boundary_race.sh <fresh-db-name> <workspace-key>
set -u
DB="${1:?database name required}"
KEY="${2:?workspace key required}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
RUNTIME="ws_${KEY}_runtime"
SYNTH="ws_${KEY}_synth_exec"

run_case () {   # $1 = label, $2 = remaining window SQL interval, $3 = expected reversal count
  local label="$1" remain="$2" expect="$3"
  local sid="e6600000-0000-0000-0000-00000000000$4"
  local eid="a6600000-0000-0000-0000-00000000000$4"
  local key="lb-$4"

  psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<SQL || { echo "FAIL $label fixture"; exit 2; }
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES('$sid','f6600000-0000-0000-0000-00000000000$4','Lock Boundary $4','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state)
VALUES('$eid','$sid',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES(gen_random_uuid(),'$eid','b6600000-0000-0000-0000-000000000001',true,'active',now());
SET SESSION AUTHORIZATION $SYNTH;
SELECT activate_student_enrollment_synthetic('$key','$eid','c6600000-0000-0000-0000-000000000001',1,1,
  'b6600000-0000-0000-0000-000000000001', now()+interval '30 days');
RESET SESSION AUTHORIZATION;
-- Synthetic clock: leave exactly \$remain of the 168-hour window.
DO \$t\$ DECLARE v_id uuid; BEGIN
  SELECT entitlement_id INTO v_id FROM student_entitlements WHERE student_id='$sid';
  ALTER TABLE student_entitlements DISABLE TRIGGER student_entitlements_guard;
  UPDATE student_entitlements
     SET activated_at = clock_timestamp() - interval '168 hours' + interval '$remain'
   WHERE entitlement_id = v_id;
  ALTER TABLE student_entitlements ENABLE TRIGGER student_entitlements_guard;
END \$t\$;
SQL

  # Blocker: hold the entitlement row so the archive command must wait.
  cat > "$W/block.sql" <<SQL
BEGIN;
SELECT entitlement_id FROM student_entitlements WHERE student_id='$sid' FOR UPDATE;
SELECT pg_sleep(30);
COMMIT;
SQL
  psql -X -q -d "$DB" -f "$W/block.sql" >"$W/block.log" 2>&1 & pblock=$!

  held=0
  for _ in $(seq 1 200); do
    n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid=l.relation WHERE c.relname='student_entitlements' AND l.mode='RowShareLock' AND l.granted")"
    if [ "$n" -ge 1 ]; then held=1; break; fi
  done
  if [ "$held" != "1" ]; then echo "FAIL $label blocker never took the lock"; kill "$pblock" 2>/dev/null; exit 2; fi

  # The archive command starts now and blocks on the entitlement row.
  cat > "$W/arc.sql" <<SQL
SET SESSION AUTHORIZATION $RUNTIME;
SELECT archive_student_enrollment('arc-$4','$eid',1,'b6600000-0000-0000-0000-000000000001','lock boundary');
SQL
  psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/arc.sql" >"$W/arc.log" 2>&1 & parc=$!

  blocked=0
  for _ in $(seq 1 400); do
    n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%archive_student_enrollment%'")"
    if [ "$n" -ge 1 ]; then blocked=1; break; fi
  done
  if [ "$blocked" != "1" ]; then echo "FAIL $label archive never blocked"; kill "$pblock" "$parc" 2>/dev/null; exit 2; fi

  # Hold the lock well past the remaining window, then release it.
  psql -X -tA -d "$DB" -c "SELECT pg_sleep(8)" >/dev/null
  psql -X -tA -d "$DB" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname=current_database() AND query LIKE '%pg_sleep(30)%' AND pid<>pg_backend_pid()" >/dev/null
  wait "$pblock" 2>/dev/null
  wait "$parc"; earc=$?

  rev="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM credit_transactions WHERE student_id='$sid' AND transaction_kind='reversal'")"
  st="$(psql -X -tA -d "$DB" -c "SELECT state FROM student_entitlements WHERE student_id='$sid'")"
  ret="$(psql -X -tA -d "$DB" -c "SELECT credit_returned FROM archive_command_log WHERE idempotency_key='arc-$4'")"
  echo "$label: archive exit=$earc reversals=$rev entitlement_state=$st credit_returned=$ret"
  if [ "$earc" -ne 0 ]; then echo "FAIL $label archive command failed"; cat "$W/arc.log"; return 1; fi
  if [ "$rev" != "$expect" ]; then echo "FAIL $label expected $expect reversal(s), got $rev"; return 1; fi
  return 0
}

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL' || { echo "FAIL WS-CRD-LOCK fixture setup"; exit 2; }
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a6500000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status)
VALUES('b6600000-0000-0000-0000-000000000001','c6600000-0000-0000-0000-000000000001','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES('b6600000-0000-0000-0000-000000000001','counselor');
INSERT INTO credit_wallets(wallet_id,unit_code) VALUES('c6600000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'c6600000-0000-0000-0000-000000000001','grant',50,'lock-boundary-grant','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value) VALUES('active_students',0,9);
SQL

ok=1
run_case "WS-CRD-LOCK-01 window closes while the command waits on the lock" "2 seconds" 0 1 || ok=0
run_case "WS-CRD-LOCK-02 control: window still open after the same wait"    "1 hour"    1 2 || ok=0

if [ "$ok" = "1" ]; then
  echo "PASS WS-CRD-LOCK-01 the reversal window is decided from the clock read AFTER the lock (no credit returned)"
  echo "PASS WS-CRD-LOCK-02 control case still returns credit after the same lock wait"
  exit 0
fi
exit 1
