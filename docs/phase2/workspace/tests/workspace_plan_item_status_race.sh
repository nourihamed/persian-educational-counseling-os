#!/usr/bin/env bash
# WS-PLAN-01 — TWO CONCURRENT STATUS TRANSITIONS FROM THE SAME STATE.
#
# The claim under test: if two sessions both see a plan item as `planned` and each records a transition
# (one to in_progress, one to completed), exactly one succeeds. History never forks into two different
# "transition number 1" rows.
#
# Why a serial test cannot show this: the stale-transition check reads the item's current status. Under
# READ COMMITTED, the second session cannot see the first session's UNCOMMITTED row, so it passes that
# check too. What makes the outcome correct is the unique key (plan_item_id, seq_no). The second insert
# waits on the first transaction's index entry and then fails with unique_violation (23505).
#
# Coordination is deterministic: session A inserts and holds its transaction until it receives an
# explicit go signal. The driver sends that signal only after OBSERVING session B blocked in
# pg_stat_activity. A is signalled to COMMIT and is never killed, because killing it would abort its
# insert and let B succeed legitimately.
#
# Sensitivity (measured): with the unique constraint dropped, B does not block and both commit, giving
# two rows with seq_no = 1. WS-PLN-RACE-01 then fails (B did not block), and WS-PLN-RACE-03 would fail
# on a forked history.
#
# Synthetic only (D-014). Usage: bash workspace_plan_item_status_race.sh <fresh-db> <workspace-key> [nounique]
set -u
DB="${1:?database}"; KEY="${2:?key}"; MODE="${3:-}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
RT="ws_${KEY}_synth_plan_writer"   # F-01: the runtime cannot write transitions; only the synthetic writer can
ITEM='a3600000-0000-0000-0000-000000000001'
STU='e3000000-0000-0000-0000-000000000001'

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<SQL || { echo "FAIL WS-PLN-RACE fixture setup"; exit 2; }
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type) VALUES (true,'a3000000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status) VALUES ('b3000000-0000-0000-0000-00000000000a','c3000000-0000-0000-0000-00000000000a','active');
INSERT INTO membership_roles(membership_id,role_key) VALUES ('b3000000-0000-0000-0000-00000000000a','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state) VALUES ('$STU',gen_random_uuid(),'Race S','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state) VALUES ('a3100000-0000-0000-0000-000000000001','$STU',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES (gen_random_uuid(),'a3100000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-00000000000a',true,'active',clock_timestamp());
INSERT INTO subjects(subject_id,subject_key,title,grade_key,source_kind,status) VALUES ('a3200000-0000-0000-0000-000000000001','race-s','S','grade_10','workspace_custom','active');
INSERT INTO chapters(chapter_id,subject_id,title,order_no) VALUES ('a3210000-0000-0000-0000-000000000001','a3200000-0000-0000-0000-000000000001','C',1);
INSERT INTO topics(topic_id,chapter_id,title,order_no) VALUES ('a3220000-0000-0000-0000-000000000001','a3210000-0000-0000-0000-000000000001','T',1);
INSERT INTO student_plans(plan_id,student_id) VALUES ('a3500000-0000-0000-0000-000000000001','$STU');
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id)
VALUES ('a3510000-0000-0000-0000-000000000001','a3500000-0000-0000-0000-000000000001',1,'{}','manual-v1','{}','draft','b3000000-0000-0000-0000-00000000000a');
INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
VALUES ('$ITEM','a3510000-0000-0000-0000-000000000001','a3500000-0000-0000-0000-000000000001','$STU',1,'a3220000-0000-0000-0000-000000000001','2026-11-21','Asia/Tehran','b3000000-0000-0000-0000-00000000000a');
-- F-03: transitions are refused on a DRAFT version's items, so the plan is published first.
UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='a3510000-0000-0000-0000-000000000001';
-- Scratch coordination table: no student_id, so no guard or barrier applies to it.
CREATE TABLE pln_race_signal(name text PRIMARY KEY);
GRANT SELECT, INSERT ON pln_race_signal TO PUBLIC;
SQL
if [ "$MODE" = "nounique" ]; then
  psql -X -q -d "$DB" -c "ALTER TABLE plan_item_status_events DROP CONSTRAINT plan_item_status_events_plan_item_id_seq_no_key" >/dev/null
  echo "NEGATIVE CONTROL: unique (plan_item_id, seq_no) dropped"
fi

cat > "$W/a.sql" <<SQL
SET SESSION AUTHORIZATION $RT;
BEGIN;
INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
VALUES (gen_random_uuid(),'$ITEM','$STU',1,'planned','in_progress','race-a','membership','b3000000-0000-0000-0000-00000000000a');
DO \$\$ BEGIN
  FOR i IN 1..1200 LOOP
    EXIT WHEN EXISTS (SELECT 1 FROM public.pln_race_signal WHERE name='go');
    PERFORM pg_sleep(0.05);
  END LOOP;
END \$\$;
COMMIT;
SQL
psql -X -q -d "$DB" -f "$W/a.sql" >"$W/a.log" 2>&1 & pa=$!

held=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND query LIKE '%pln_race_signal%' AND state='active'")"
  [ "${n:-0}" -ge 1 ] && { held=1; break; }
  kill -0 "$pa" 2>/dev/null || break
  sleep 0.05
done
[ "$held" = "1" ] || { echo "FAIL WS-PLN-RACE-01 session A never reached its wait"; cat "$W/a.log"; exit 2; }

cat > "$W/b.sql" <<SQL
SET SESSION AUTHORIZATION $RT;
INSERT INTO plan_item_status_events(event_id,plan_item_id,student_id,seq_no,from_status,to_status,reason_note,actor_kind,actor_membership_id)
VALUES (gen_random_uuid(),'$ITEM','$STU',1,'planned','completed','race-b','membership','b3000000-0000-0000-0000-00000000000a');
SQL
psql -X -q -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!

blocked=0
for _ in $(seq 1 200); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%race-b%'")"
  [ "${n:-0}" -ge 1 ] && { blocked=1; break; }
  kill -0 "$pb" 2>/dev/null || break
  sleep 0.05
done
psql -X -q -d "$DB" -c "INSERT INTO pln_race_signal(name) VALUES('go')" >/dev/null
wait "$pa"; ea=$?; wait "$pb"; eb=$?

rows="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM plan_item_status_events WHERE plan_item_id='$ITEM'")"
seq1="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM plan_item_status_events WHERE plan_item_id='$ITEM' AND seq_no=1")"
cur="$(psql -X -tA -d "$DB" -c "SELECT status FROM plan_item_current_status WHERE plan_item_id='$ITEM'")"
echo "A exit=$ea  B exit=$eb  rows=$rows  seq_no=1 rows=$seq1  current=$cur"

ok=1
if [ "$blocked" = "1" ]; then echo "PASS WS-PLN-RACE-01 the second transition BLOCKED on the first one's uncommitted sequence number"
else echo "FAIL WS-PLN-RACE-01 the second transition did not block; nothing serializes concurrent transitions"; ok=0; fi
if [ "$ea" -eq 0 ] && grep -q "duplicate key value" "$W/b.log"; then
  echo "PASS WS-PLN-RACE-02 the first transition committed and the second was refused with unique_violation"
else echo "FAIL WS-PLN-RACE-02 expected A to commit and B to fail on the unique key; B said: $(tail -1 "$W/b.log")"; ok=0; fi
if [ "$rows" = "1" ] && [ "$seq1" = "1" ] && [ "$cur" = "in_progress" ]; then
  echo "PASS WS-PLN-RACE-03 history did not fork: one transition, current status in_progress"
else echo "FAIL WS-PLN-RACE-03 history forked or is wrong (rows=$rows, seq1=$seq1, current=$cur)"; ok=0; fi
[ "$ok" = "1" ] || exit 1
echo "PLAN ITEM STATUS RACE COMPLETED"
