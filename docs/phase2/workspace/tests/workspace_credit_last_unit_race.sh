#!/usr/bin/env bash
# Batch 3 — CONCURRENT DEBITS FOR THE LAST AVAILABLE CREDIT.
#
# The claim under test: two activations for DIFFERENT students, racing for a wallet that holds exactly one
# unit of spendable credit, produce exactly one debit — and the spendable balance never goes negative.
#
# This is the concurrency half of "no negative or inconsistent spendable balance". The serial half is
# CRD-39..41; neither implies the other. A guard that reads the balance and then inserts is correct when
# run serially and wrong under concurrency, because two sessions can each read the same balance and each
# conclude there is enough. What makes it correct here is the `FOR UPDATE` lock the guard takes on the
# wallet row before it computes anything.
#
# WHY THIS IS NOT THE EXISTING ACTIVATION RACE
#   workspace_activation_race.sh has both sessions activate the SAME enrollment, so it tests idempotency
#   and serialization of one command. Nothing there competes for scarce credit: the wallet has 10 and one
#   debit of 8 is requested. Two different students contending for the last unit was untested.
#
# COORDINATION IS DETERMINISTIC, NOT TIMING-BASED
#   Session A opens a transaction and activates, which takes the wallet row lock and holds it. The driver
#   waits until that lock is observably held in pg_locks, and only then starts session B, which must block
#   on the same row. The driver confirms B is blocked before letting A commit. The outcome cannot depend on
#   scheduling: either B blocks on the wallet row or the test fails.
#
# SENSITIVITY, MEASURED (recorded in docs/phase2/IMPLEMENTATION_RESPONSE_2026-11-14.md section 8)
#   Replacing the guard with a body that computes the same balance but takes NO wallet lock produces:
#       debits=2  ledger=-1  available=-1  active enrollments=2  entitlements=2  capacity used=2
#   and WS-CRD-LAST-02/03/04/05 all fail. So this script is sensitive to the lock, not merely passing.
#
#   One nuance worth stating, because it would otherwise invite a wrong reading: in that negative control
#   the "second activation is blocked" observation STILL appears. The activation command takes other row
#   locks of its own (the enrollment, the capacity counter), so B blocks regardless. The blocking
#   observation therefore proves only that the sessions genuinely overlapped — it is NOT evidence for the
#   wallet lock. The outcome assertions below are the evidence.
#
# Synthetic only (D-014). Usage: bash workspace_credit_last_unit_race.sh <fresh-db-name> <workspace-key>
set -u
DB="${1:?database name required}"
KEY="${2:?workspace key required}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
SYNTH="ws_${KEY}_synth_exec"
WALLET='c9300000-0000-0000-0000-000000000001'
ENR_A='a9300000-0000-0000-0000-00000000000a'
ENR_B='a9300000-0000-0000-0000-00000000000b'

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<SQL || { echo "FAIL WS-CRD-LAST fixture setup"; exit 2; }
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a9300000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status)
VALUES('b9300000-0000-0000-0000-000000000001','c9300000-0000-0000-0000-000000000009','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES('b9300000-0000-0000-0000-000000000001','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES
 ('e9300000-0000-0000-0000-00000000000a',gen_random_uuid(),'Last Unit A','grade_10','active'),
 ('e9300000-0000-0000-0000-00000000000b',gen_random_uuid(),'Last Unit B','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES
 ('$ENR_A','e9300000-0000-0000-0000-00000000000a',1,'requested'),
 ('$ENR_B','e9300000-0000-0000-0000-00000000000b',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at) VALUES
 (gen_random_uuid(),'$ENR_A','b9300000-0000-0000-0000-000000000001',true,'active',now()),
 (gen_random_uuid(),'$ENR_B','b9300000-0000-0000-0000-000000000001',true,'active',now());
-- Exactly ONE unit of spendable credit, and capacity for both, so credit is the only scarce resource.
INSERT INTO credit_wallets(wallet_id,unit_code) VALUES('$WALLET','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'$WALLET','grant',1,'last-unit-grant','synthetic single credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value) VALUES('active_students',0,5);
-- Scratch coordination table. It carries no student_id and no enrollment_id, so no guard or barrier
-- applies to it and it cannot mask the behaviour under test.
CREATE TABLE crd_race_signal(name text PRIMARY KEY);
GRANT SELECT, INSERT ON crd_race_signal TO PUBLIC;
SQL

# Session A: activate student A, then wait for an explicit go signal and COMMIT.
# A is signalled, never killed. Terminating it would ABORT its transaction, release the credit, and let B
# succeed legitimately — which is not the case under test. An earlier version of this script did exactly
# that and reported a misleading result.
cat > "$W/a.sql" <<SQL
SET SESSION AUTHORIZATION $SYNTH;
BEGIN;
SELECT activate_student_enrollment_synthetic('last-unit-a','$ENR_A','$WALLET',1,1,
  'b9300000-0000-0000-0000-000000000001','2099-01-01 00:00:00+00'::timestamptz);
DO \$\$ BEGIN
  FOR i IN 1..1200 LOOP
    EXIT WHEN EXISTS (SELECT 1 FROM public.crd_race_signal WHERE name='go');
    PERFORM pg_sleep(0.05);
  END LOOP;
END \$\$;
COMMIT;
SQL
psql -X -q -d "$DB" -f "$W/a.sql" >"$W/a.log" 2>&1 & pa=$!

held=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid=l.relation WHERE c.relname='credit_wallets' AND l.granted AND l.mode IN ('RowShareLock','RowExclusiveLock')")"
  if [ "${n:-0}" -ge 1 ]; then held=1; break; fi
  if ! kill -0 "$pa" 2>/dev/null; then break; fi
done
if [ "$held" != "1" ]; then
  echo "FAIL WS-CRD-LAST-01 session A never took the wallet row lock"
  kill "$pa" 2>/dev/null; cat "$W/a.log"; exit 2
fi

# Session B: activate student B against the same single credit. It must BLOCK on A's wallet lock.
cat > "$W/b.sql" <<SQL
SET SESSION AUTHORIZATION $SYNTH;
SELECT activate_student_enrollment_synthetic('last-unit-b','$ENR_B','$WALLET',1,1,
  'b9300000-0000-0000-0000-000000000001','2099-01-01 00:00:00+00'::timestamptz);
SQL
psql -X -q -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!

blocked=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%last-unit-b%'")"
  if [ "${n:-0}" -ge 1 ]; then blocked=1; break; fi
  if ! kill -0 "$pb" 2>/dev/null; then break; fi
done
if [ "$blocked" != "1" ]; then
  echo "FAIL WS-CRD-LAST-01 session B did NOT block on the wallet row: ledger inserts are not serialized,"
  echo "                   so two debits can each read the same balance and both succeed"
  cat "$W/b.log"
  psql -X -q -d "$DB" -c "INSERT INTO crd_race_signal(name) VALUES('go')" >/dev/null 2>&1
  wait "$pa" 2>/dev/null; wait "$pb" 2>/dev/null; exit 1
fi
echo "observed: the second activation is blocked on the wallet row held by the first"

# Let A COMMIT (signalled, not killed), then see what B did.
psql -X -q -d "$DB" -c "INSERT INTO crd_race_signal(name) VALUES('go')" >/dev/null
wait "$pa"; ea=$?
wait "$pb"; eb=$?

debits="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM credit_transactions WHERE wallet_id='$WALLET' AND transaction_kind='activation_debit'")"
ledger="$(psql -X -tA -d "$DB" -c "SELECT ledger_balance FROM credit_wallet_balances WHERE wallet_id='$WALLET'")"
avail="$(psql -X -tA -d "$DB" -c "SELECT available_balance FROM credit_wallet_balances WHERE wallet_id='$WALLET'")"
active="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM enrollments WHERE enrollment_id IN ('$ENR_A','$ENR_B') AND state='active'")"
ents="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM student_entitlements")"
cap="$(psql -X -tA -d "$DB" -c "SELECT current_value FROM workspace_capacity_counters WHERE dimension_key='active_students'")"

echo "A exit=$ea  B exit=$eb  debits=$debits  ledger=$ledger  available=$avail  active enrollments=$active  entitlements=$ents  capacity used=$cap"
echo "B said: $(tail -2 "$W/b.log" | tr '\n' ' ' | cut -c1-200)"

ok=1
[ "${ea:-1}" -eq 0 ] || { echo "FAIL WS-CRD-LAST-02 session A did not commit; the test's premise does not hold"; cat "$W/a.log"; ok=0; }
[ "$debits" = "1" ] || { echo "FAIL WS-CRD-LAST-02 expected exactly one activation debit, found $debits"; ok=0; }
[ "$avail" = "0" ] || { echo "FAIL WS-CRD-LAST-02 the available balance is $avail, expected 0"; ok=0; }
if [ -n "$avail" ] && [ "$avail" -lt 0 ]; then
  echo "FAIL WS-CRD-LAST-03 the spendable balance went NEGATIVE ($avail)"; ok=0
fi
[ "$active" = "1" ] || { echo "FAIL WS-CRD-LAST-04 expected exactly one active enrollment, found $active"; ok=0; }
[ "$ents" = "1" ] || { echo "FAIL WS-CRD-LAST-04 expected exactly one entitlement, found $ents"; ok=0; }
[ "$cap" = "1" ] || { echo "FAIL WS-CRD-LAST-04 expected exactly one capacity slot used, found $cap"; ok=0; }
if ! grep -q "insufficient student credit" "$W/b.log"; then
  echo "FAIL WS-CRD-LAST-05 the loser was not refused for insufficient credit:"; cat "$W/b.log"; ok=0
fi

if [ "$ok" = "1" ]; then
  echo "PASS WS-CRD-LAST-01 the second debit blocked on the wallet row instead of reading a stale balance"
  echo "PASS WS-CRD-LAST-02 exactly one debit landed and the available balance is 0"
  echo "PASS WS-CRD-LAST-03 the spendable balance never went negative"
  echo "PASS WS-CRD-LAST-04 exactly one enrollment, one entitlement and one capacity slot resulted"
  echo "PASS WS-CRD-LAST-05 the losing activation was refused for insufficient credit, with nothing partial left"
  exit 0
fi
exit 1
