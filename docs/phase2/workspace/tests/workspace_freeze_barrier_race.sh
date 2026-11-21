#!/usr/bin/env bash
# Batch 1 - IN-FLIGHT TRANSACTION BARRIER (Saga contract section 3: source freeze and write drain).
#
# The claim under test: a source freeze cannot complete while a transaction is still writing that
# student's data, the in-flight write is DRAINED rather than discarded, and no write slips past the
# barrier afterwards.
#
# Coordination is deterministic, not a timing race. The in-flight writer opens a transaction, writes the
# student, and then waits for an explicit go signal. The driver only sends that signal after it has
# OBSERVED the freeze command blocked on a lock in pg_stat_activity. The outcome therefore cannot depend
# on scheduling: either the freeze blocks on the writer or the test fails.
#
# TWO MODES, BECAUSE ONE OF THEM PROVES NOTHING ON ITS OWN
#   mode "fk"    the in-flight writer inserts a study_sessions row. study_sessions has a foreign key to
#                students, so PostgreSQL itself takes a KEY SHARE lock on the student row. The freeze
#                would block here even if this project had written no barrier at all. This mode is the
#                realistic end-to-end path, but it is NOT evidence that the barrier works.
#   mode "nofk"  the in-flight writer inserts a class_session_participants row. That table is
#                student-scoped (it carries student_id and is covered by the write barrier) but its
#                foreign keys point at class_participants and class_sessions, NOT at students. No
#                foreign-key lock on the student row exists. The freeze blocks here ONLY because
#                assert_student_not_frozen() takes `FOR SHARE` on the student row. This mode is the one
#                that actually tests the barrier this project added.
#
# NEGATIVE CONTROL (executed 2026-11-14; recorded in docs/phase2/IMPLEMENTATION_RESPONSE_2026-11-14.md):
#   assert_student_not_frozen() was replaced with a version identical except that the `FOR SHARE` lock
#   was removed, and this script was re-run against both modes. Measured result:
#       mode "fk"    -> still PASSES  (exit 0)  : masked by the foreign-key lock, proves nothing
#       mode "nofk"  -> FAILS         (exit 2)  : "the in-flight writer never took the student row lock"
#   So mode "nofk" is sensitive to the implementation and mode "fk" is not. Both are run: "nofk" is the
#   evidence, "fk" is the realistic path. A reviewer who wants only one should read the "nofk" result.
#
# Sequence (both modes):
#   1. writer A  BEGIN; write the student's data        -> takes the FOR SHARE lock on the student row
#   2. freeze B  freeze_student_for_transfer(...)       -> must BLOCK (verified in pg_stat_activity)
#   3. driver    sends the go signal; A COMMITS (it is not killed)
#   4. freeze B  completes; its barrier watermark is a LATER txid than A's
#   5. writer C  writes after the barrier               -> refused by the write barrier
#
# Synthetic only (D-014). Usage: bash workspace_freeze_barrier_race.sh <fresh-db> <workspace-key> [fk|nofk]
set -u
DB="${1:?database name required}"
KEY="${2:?workspace key required}"
MODE="${3:-nofk}"
case "$MODE" in fk|nofk) : ;; *) echo "FAIL unknown mode '$MODE' (expected fk or nofk)"; exit 2 ;; esac
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
RUNTIME="ws_${KEY}_runtime"
CTL="ws_${KEY}_transfer_ctl"
SYNTH="ws_${KEY}_synth_exec"
STUDENT='e9500000-0000-0000-0000-000000000001'
ENROLL='a9500000-0000-0000-0000-000000000001'
CLASS='c9900000-0000-0000-0000-000000000001'
CSESSION='c9900000-0000-0000-0000-000000000002'
INFLIGHT='a9700000-0000-0000-0000-000000000001'

echo "=== in-flight transaction barrier, mode=$MODE ==="

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<SQL || { echo "FAIL WS-FRZ-BARRIER fixture setup"; exit 2; }
-- Scratch coordination table. It carries neither student_id nor enrollment_id, so it is outside the
-- write barrier's coverage by construction and cannot mask the behaviour under test.
CREATE TABLE frz_race_signal(name text PRIMARY KEY, txid bigint);
GRANT SELECT, INSERT ON frz_race_signal TO PUBLIC;

INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES(true,'a9400000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status)
VALUES('b9500000-0000-0000-0000-000000000001','c9500000-0000-0000-0000-000000000001','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES('b9500000-0000-0000-0000-000000000001','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES('$STUDENT','f9500000-0000-0000-0000-000000000001','Barrier Subject','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state)
VALUES('$ENROLL','$STUDENT',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES(gen_random_uuid(),'$ENROLL','b9500000-0000-0000-0000-000000000001',true,'active',now());
INSERT INTO credit_wallets(wallet_id,unit_code) VALUES('c9600000-0000-0000-0000-000000000001','CRD');
INSERT INTO credit_transactions(transaction_id,wallet_id,transaction_kind,amount,idempotency_key,reason)
VALUES(gen_random_uuid(),'c9600000-0000-0000-0000-000000000001','grant',50,'barrier-fixture-grant','synthetic opening credit');
INSERT INTO workspace_capacity_counters(dimension_key,current_value,max_value) VALUES('active_students',0,5);

-- class fixture for the "nofk" mode: a student-scoped table with NO foreign key to students
INSERT INTO classes(class_id,class_kind,title) VALUES('$CLASS','online','Barrier Class');
INSERT INTO class_sessions(class_session_id,class_id,starts_at,ends_at,timezone_name)
VALUES('$CSESSION','$CLASS',now(),now()+interval '1 hour','Asia/Tehran');
INSERT INTO class_participants(class_id,student_id,state) VALUES('$CLASS','$STUDENT','enrolled');

SET SESSION AUTHORIZATION $SYNTH;
SELECT activate_student_enrollment_synthetic('frz-barrier-act','$ENROLL','c9600000-0000-0000-0000-000000000001',1,5,
  'b9500000-0000-0000-0000-000000000001','2099-01-01 00:00:00+00'::timestamptz);
RESET SESSION AUTHORIZATION;
SQL

if [ "$MODE" = "fk" ]; then
  INFLIGHT_SQL="INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES('$INFLIGHT','$STUDENT',now(),42);"
  COUNT_SQL="SELECT count(*) FROM study_sessions WHERE study_session_id='$INFLIGHT'"
  TOTAL_SQL="SELECT count(*) FROM study_sessions WHERE student_id='$STUDENT'"
  AFTER_SQL="INSERT INTO study_sessions(study_session_id,student_id,started_at,actual_minutes) VALUES(gen_random_uuid(),'$STUDENT',now(),5);"
else
  INFLIGHT_SQL="INSERT INTO class_session_participants(class_session_id,class_id,student_id,attendance) VALUES('$CSESSION','$CLASS','$STUDENT','attended');"
  COUNT_SQL="SELECT count(*) FROM class_session_participants WHERE class_session_id='$CSESSION' AND student_id='$STUDENT'"
  TOTAL_SQL="SELECT count(*) FROM class_session_participants WHERE student_id='$STUDENT'"
  AFTER_SQL="UPDATE class_session_participants SET attendance='absent' WHERE class_session_id='$CSESSION' AND student_id='$STUDENT';"
fi

# ---- 1. the in-flight writer: write, record its own txid, then wait for the go signal and COMMIT.
cat > "$W/writer.sql" <<SQL
SET SESSION AUTHORIZATION $RUNTIME;
BEGIN;
$INFLIGHT_SQL
INSERT INTO frz_race_signal(name,txid) VALUES('writer',txid_current());
DO \$\$ BEGIN
  FOR i IN 1..1200 LOOP
    EXIT WHEN EXISTS (SELECT 1 FROM frz_race_signal WHERE name='go');
    PERFORM pg_sleep(0.05);
  END LOOP;
END \$\$;
COMMIT;
SQL
psql -X -q -d "$DB" -f "$W/writer.sql" >"$W/writer.log" 2>&1 & pwriter=$!

held=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid=l.relation WHERE c.relname='students' AND l.granted AND l.mode='RowShareLock'")"
  if [ "${n:-0}" -ge 1 ]; then held=1; break; fi
  if ! kill -0 "$pwriter" 2>/dev/null; then break; fi
done
if [ "$held" != "1" ]; then
  echo "FAIL WS-FRZ-BARRIER-01 the in-flight writer never took the student row lock"
  kill "$pwriter" 2>/dev/null; cat "$W/writer.log"; exit 2
fi

# ---- 2. the freeze must BLOCK on the in-flight writer.
cat > "$W/freeze.sql" <<SQL
SET SESSION AUTHORIZATION $CTL;
SELECT freeze_student_for_transfer('a9800000-0000-0000-0000-000000000001','frz-barrier-token','$STUDENT',
  'd9500000-0000-0000-0000-000000000001',1,'ctl/0.1',0,now());
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/freeze.sql" >"$W/freeze.log" 2>&1 & pfreeze=$!

blocked=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%freeze_student_for_transfer%'")"
  if [ "${n:-0}" -ge 1 ]; then blocked=1; break; fi
  if ! kill -0 "$pfreeze" 2>/dev/null; then break; fi
done
if [ "$blocked" != "1" ]; then
  echo "FAIL WS-FRZ-BARRIER-01 (mode=$MODE) the freeze did NOT block on the in-flight writer: there is no transaction barrier"
  cat "$W/freeze.log"
  psql -X -q -d "$DB" -c "INSERT INTO frz_race_signal(name) VALUES('go')" >/dev/null 2>&1
  wait "$pwriter" 2>/dev/null; wait "$pfreeze" 2>/dev/null; exit 1
fi
echo "observed: freeze_student_for_transfer is blocked on the in-flight writer's lock"

# ---- 3. let the writer COMMIT (it is signalled, not killed: the write must survive).
psql -X -q -d "$DB" -c "INSERT INTO frz_race_signal(name) VALUES('go')" >/dev/null
wait "$pwriter"; ewriter=$?
wait "$pfreeze"; efreeze=$?

# ---- 4/5. assertions.
state="$(psql -X -tA -d "$DB" -c "SELECT state FROM student_transfer_freezes WHERE freeze_token='frz-barrier-token'")"
mark="$(psql -X -tA -d "$DB" -c "SELECT barrier_watermark_txid FROM student_transfer_freezes WHERE freeze_token='frz-barrier-token'")"
writer_txid="$(psql -X -tA -d "$DB" -c "SELECT txid FROM frz_race_signal WHERE name='writer'")"
survived="$(psql -X -tA -d "$DB" -c "$COUNT_SQL")"
psql -X -d "$DB" >"$W/after.log" 2>&1 <<SQL
SET SESSION AUTHORIZATION $RUNTIME;
$AFTER_SQL
SQL
after_count="$(psql -X -tA -d "$DB" -c "$TOTAL_SQL")"

echo "writer exit=$ewriter  freeze exit=$efreeze  state=$state  watermark=$mark  writer_txid=$writer_txid"
echo "in-flight row survived=$survived  rows for the student after the post-barrier attempt=$after_count"

ok=1
[ "$ewriter" -eq 0 ] || { echo "FAIL WS-FRZ-BARRIER-02 the in-flight writer did not commit"; cat "$W/writer.log"; ok=0; }
[ "$efreeze" -eq 0 ] || { echo "FAIL WS-FRZ-BARRIER-01 the freeze did not complete after the writer settled"; cat "$W/freeze.log"; ok=0; }
[ "$state" = "frozen" ] || { echo "FAIL WS-FRZ-BARRIER-01 unexpected freeze state: $state"; ok=0; }
[ "$survived" = "1" ] || { echo "FAIL WS-FRZ-BARRIER-02 the in-flight write was lost; the barrier must drain, not discard"; ok=0; }
if [ -z "$mark" ] || [ -z "$writer_txid" ] || [ "$mark" -le "$writer_txid" ]; then
  echo "FAIL WS-FRZ-BARRIER-03 the barrier watermark ($mark) is not later than the drained writer ($writer_txid)"; ok=0
fi
if ! grep -q "frozen for transfer case" "$W/after.log"; then
  echo "FAIL WS-FRZ-BARRIER-04 the post-barrier write was not refused by the freeze barrier:"; cat "$W/after.log"; ok=0
fi
[ "$after_count" = "1" ] || { echo "FAIL WS-FRZ-BARRIER-04 a write slipped past the barrier (rows now $after_count)"; ok=0; }

if [ "$ok" = "1" ]; then
  echo "PASS WS-FRZ-BARRIER-01 (mode=$MODE) the freeze blocked until the in-flight transaction settled"
  echo "PASS WS-FRZ-BARRIER-02 (mode=$MODE) the in-flight write survived the barrier (drained, not discarded)"
  echo "PASS WS-FRZ-BARRIER-03 (mode=$MODE) the barrier watermark is later than the drained writer's transaction"
  echo "PASS WS-FRZ-BARRIER-04 (mode=$MODE) no write is accepted after the barrier closed"
  exit 0
fi
exit 1
