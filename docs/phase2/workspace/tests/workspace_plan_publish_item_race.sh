#!/usr/bin/env bash
# WS-PLAN-01 H-03 — PlanItem INSERT vs PlanVersion publication, both lock orders.
# Synthetic-only. Requires the complete Phase 2 Workspace draft schema and workspace_key roles.
# Case A: item INSERT obtains FOR SHARE first; publication must wait, then see the committed item.
# Case B: publication obtains NO KEY UPDATE first; item INSERT must wait, then reject the published version.
set -euo pipefail
DB="${1:?database}"; KEY="${2:?workspace key}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
WRITER="ws_${KEY}_synth_plan_writer"
STU="e7500000-0000-0000-0000-000000000001"
V1="a7510000-0000-0000-0000-000000000001"
V2="a7510000-0000-0000-0000-000000000002"
V3="a7510000-0000-0000-0000-000000000003"
V4="a7510000-0000-0000-0000-000000000004"
ITEM_A="a7520000-0000-0000-0000-000000000001"
ITEM_B="a7520000-0000-0000-0000-000000000002"
ITEM_B2="a7520000-0000-0000-0000-000000000003"
ITEM_C="a7520000-0000-0000-0000-000000000004"
ITEM_D="a7520000-0000-0000-0000-000000000005"
ITEM_D2="a7520000-0000-0000-0000-000000000006"

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<SQL
INSERT INTO workspace_profile(singleton,workspace_id,workspace_type)
VALUES (true,'a7500000-0000-0000-0000-000000000001','organization');
INSERT INTO workspace_memberships(membership_id,platform_user_id,status)
VALUES ('b7500000-0000-0000-0000-000000000001','c7500000-0000-0000-0000-000000000001','active');
INSERT INTO membership_roles(membership_id,role_key)
VALUES ('b7500000-0000-0000-0000-000000000001','counselor');
INSERT INTO students(student_id,platform_student_id,display_name,grade_key,lifecycle_state)
VALUES ('$STU',gen_random_uuid(),'Publish Race','grade_10','active');
INSERT INTO enrollments(enrollment_id,student_id,ownership_generation,state)
VALUES ('a7530000-0000-0000-0000-000000000001','$STU',1,'requested');
INSERT INTO counselor_assignments(assignment_id,enrollment_id,counselor_membership_id,is_responsible,state,accepted_at)
VALUES ('a7540000-0000-0000-0000-000000000001','a7530000-0000-0000-0000-000000000001',
        'b7500000-0000-0000-0000-000000000001',true,'active',clock_timestamp());
INSERT INTO subjects(subject_id,subject_key,title,grade_key,source_kind,status)
VALUES ('a7550000-0000-0000-0000-000000000001','publish-race','Race','grade_10','workspace_custom','active');
INSERT INTO chapters(chapter_id,subject_id,title,order_no)
VALUES ('a7560000-0000-0000-0000-000000000001','a7550000-0000-0000-0000-000000000001','Race',1);
INSERT INTO topics(topic_id,chapter_id,title,order_no)
VALUES ('a7570000-0000-0000-0000-000000000001','a7560000-0000-0000-0000-000000000001','Race topic',1);
INSERT INTO student_plans(plan_id,student_id) VALUES
 ('a7580000-0000-0000-0000-000000000001','$STU'),
 ('a7580000-0000-0000-0000-000000000002','$STU'),
 ('a7580000-0000-0000-0000-000000000003','$STU'),
 ('a7580000-0000-0000-0000-000000000004','$STU');
INSERT INTO student_plan_versions(plan_version_id,plan_id,version_no,input_snapshot,rule_version,plan_content,status,created_by_membership_id)
VALUES
 ('$V1','a7580000-0000-0000-0000-000000000001',1,'{}','race-v1','{}','draft','b7500000-0000-0000-0000-000000000001'),
 ('$V2','a7580000-0000-0000-0000-000000000002',1,'{}','race-v1','{}','draft','b7500000-0000-0000-0000-000000000001'),
 ('$V3','a7580000-0000-0000-0000-000000000003',1,'{}','race-v1','{}','draft','b7500000-0000-0000-0000-000000000001'),
 ('$V4','a7580000-0000-0000-0000-000000000004',1,'{}','race-v1','{}','draft','b7500000-0000-0000-0000-000000000001');
SQL

psql -X -v ON_ERROR_STOP=1 -v workspace_key="$KEY" -q -d "$DB" \
  -f "$(dirname "$0")/workspace_principal_test_harness.sql" >/dev/null

# Seed one item in V2, so the publication-first case can pass C1 and hold the version lock.
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<SQL
SET lock_timeout='8s';
SET statement_timeout='15s';
SET SESSION AUTHORIZATION $WRITER;
BEGIN;
SELECT test_establish('counselor','b7500000-0000-0000-0000-000000000001');
INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
VALUES ('$ITEM_B','$V2','a7580000-0000-0000-0000-000000000002','$STU',1,
        'a7570000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b7500000-0000-0000-0000-000000000001'),
       ('$ITEM_D','$V4','a7580000-0000-0000-0000-000000000004','$STU',1,
        'a7570000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b7500000-0000-0000-0000-000000000001');
COMMIT;
RESET SESSION AUTHORIZATION;
SQL

# CASE A — INSERT locks the draft first; publisher blocks until the item commits, then publishes.
cat > "$W/a1.sql" <<SQL
SET SESSION AUTHORIZATION $WRITER;
BEGIN;
SELECT test_establish('counselor','b7500000-0000-0000-0000-000000000001');
INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
VALUES ('$ITEM_A','$V1','a7580000-0000-0000-0000-000000000001','$STU',1,
        'a7570000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b7500000-0000-0000-0000-000000000001');
\! touch "$W/a1_ready"
\! while [ ! -f "$W/a1_go" ]; do sleep 0.05; done
COMMIT;
RESET SESSION AUTHORIZATION;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a1.sql" >"$W/a1.log" 2>&1 & PA=$!
for _ in $(seq 1 200); do [ -f "$W/a1_ready" ] && break; kill -0 "$PA" 2>/dev/null || { cat "$W/a1.log"; exit 1; }; sleep 0.05; done
[ -f "$W/a1_ready" ] || { echo "FAIL WS-PLN-PUB-RACE-01 item session did not acquire the version lock"; cat "$W/a1.log"; exit 1; }

cat > "$W/b1.sql" <<SQL
SET lock_timeout='8s';
SET statement_timeout='15s';
BEGIN;
UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='$V1';
COMMIT;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b1.sql" >"$W/b1.log" 2>&1 & PB=$!
BLOCKED=0
for _ in $(seq 1 200); do
  N="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%$V1%'")"
  [ "${N:-0}" -ge 1 ] && { BLOCKED=1; break; }
  kill -0 "$PB" 2>/dev/null || break
  sleep 0.05
done
touch "$W/a1_go"
wait "$PA"
wait "$PB"
[ "$BLOCKED" = "1" ] || { echo "FAIL WS-PLN-PUB-RACE-01 publisher did not block behind the item insert"; cat "$W/b1.log"; exit 1; }
[ "$(psql -X -tA -d "$DB" -c "SELECT status FROM student_plan_versions WHERE plan_version_id='$V1'")" = "published" ] || { echo "FAIL WS-PLN-PUB-RACE-02 publisher did not publish after item commit"; exit 1; }
[ "$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM plan_items WHERE plan_version_id='$V1'")" = "1" ] || { echo "FAIL WS-PLN-PUB-RACE-03 published version is missing the concurrently committed item"; exit 1; }
echo "PASS WS-PLN-PUB-RACE-01/02/03 item-first: publisher waits, sees the item, and publishes"

# CASE B — Publisher locks a non-empty draft first; late item insert blocks, then fails after publication.
cat > "$W/b2.sql" <<SQL
SET lock_timeout='8s';
SET statement_timeout='15s';
BEGIN;
UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='$V2';
\! touch "$W/b2_ready"
\! while [ ! -f "$W/b2_go" ]; do sleep 0.05; done
COMMIT;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b2.sql" >"$W/b2.log" 2>&1 & PB2=$!
for _ in $(seq 1 200); do [ -f "$W/b2_ready" ] && break; kill -0 "$PB2" 2>/dev/null || { cat "$W/b2.log"; exit 1; }; sleep 0.05; done
[ -f "$W/b2_ready" ] || { echo "FAIL WS-PLN-PUB-RACE-04 publisher did not hold its row lock"; cat "$W/b2.log"; exit 1; }

cat > "$W/a2.sql" <<SQL
SET lock_timeout='8s';
SET statement_timeout='15s';
SET SESSION AUTHORIZATION $WRITER;
BEGIN;
SELECT test_establish('counselor','b7500000-0000-0000-0000-000000000001');
INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
VALUES ('$ITEM_B2','$V2','a7580000-0000-0000-0000-000000000002','$STU',2,
        'a7570000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b7500000-0000-0000-0000-000000000001');
COMMIT;
RESET SESSION AUTHORIZATION;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a2.sql" >"$W/a2.log" 2>&1 & PA2=$!
BLOCKED=0
for _ in $(seq 1 200); do
  N="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%$ITEM_B2%'")"
  [ "${N:-0}" -ge 1 ] && { BLOCKED=1; break; }
  kill -0 "$PA2" 2>/dev/null || break
  sleep 0.05
done
touch "$W/b2_go"
wait "$PB2"
set +e
wait "$PA2"
EA2=$?
set -e
[ "$BLOCKED" = "1" ] || { echo "FAIL WS-PLN-PUB-RACE-04 item insert did not block behind publication"; cat "$W/a2.log"; exit 1; }
[ "$EA2" -ne 0 ] || { echo "FAIL WS-PLN-PUB-RACE-05 late item insert unexpectedly succeeded"; cat "$W/a2.log"; exit 1; }
grep -q "only be added to a DRAFT plan version" "$W/a2.log" || { echo "FAIL WS-PLN-PUB-RACE-05 late item insert failed for an unexpected reason"; cat "$W/a2.log"; exit 1; }
[ "$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM plan_items WHERE plan_version_id='$V2'")" = "1" ] || { echo "FAIL WS-PLN-PUB-RACE-06 late item was inserted after publication"; exit 1; }
echo "PASS WS-PLN-PUB-RACE-04/05/06 publisher-first: item insert waits, then refuses published version"

# CASE C — Item INSERT obtains FOR SHARE first but ROLLS BACK; publisher waits, then C1 refuses empty publish.
cat > "$W/a3.sql" <<SQL
SET lock_timeout='8s';
SET statement_timeout='15s';
SET SESSION AUTHORIZATION $WRITER;
BEGIN;
SELECT test_establish('counselor','b7500000-0000-0000-0000-000000000001');
INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
VALUES ('$ITEM_C','$V3','a7580000-0000-0000-0000-000000000003','$STU',1,
        'a7570000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b7500000-0000-0000-0000-000000000001');
\! touch "$W/a3_ready"
\! while [ ! -f "$W/a3_go" ]; do sleep 0.05; done
ROLLBACK;
RESET SESSION AUTHORIZATION;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a3.sql" >"$W/a3.log" 2>&1 & PA3=$!
for _ in $(seq 1 200); do [ -f "$W/a3_ready" ] && break; kill -0 "$PA3" 2>/dev/null || { cat "$W/a3.log"; exit 1; }; sleep 0.05; done
[ -f "$W/a3_ready" ] || { echo "FAIL WS-PLN-PUB-RACE-07 item-first rollback session did not acquire lock"; cat "$W/a3.log"; exit 1; }
cat > "$W/b3.sql" <<SQL
SET lock_timeout='8s';
SET statement_timeout='15s';
BEGIN;
UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='$V3';
COMMIT;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b3.sql" >"$W/b3.log" 2>&1 & PB3=$!
BLOCKED=0
for _ in $(seq 1 200); do
  N="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%$V3%'")"
  [ "${N:-0}" -ge 1 ] && { BLOCKED=1; break; }
  kill -0 "$PB3" 2>/dev/null || break
  sleep 0.05
done
touch "$W/a3_go"
wait "$PA3"
set +e
wait "$PB3"
EB3=$?
set -e
[ "$BLOCKED" = "1" ] || { echo "FAIL WS-PLN-PUB-RACE-07 publisher did not wait for item-first rollback"; cat "$W/b3.log"; exit 1; }
[ "$EB3" -ne 0 ] || { echo "FAIL WS-PLN-PUB-RACE-08 publication succeeded after the only item rolled back"; cat "$W/b3.log"; exit 1; }
grep -q "EMPTY normalized" "$W/b3.log" || { echo "FAIL WS-PLN-PUB-RACE-08 publisher failed for an unexpected reason"; cat "$W/b3.log"; exit 1; }
[ "$(psql -X -tA -d "$DB" -c "SELECT status FROM student_plan_versions WHERE plan_version_id='$V3'")" = "draft" ] || { echo "FAIL WS-PLN-PUB-RACE-09 rollback case changed version state"; exit 1; }
[ "$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM plan_items WHERE plan_version_id='$V3'")" = "0" ] || { echo "FAIL WS-PLN-PUB-RACE-09 rolled-back item remains"; exit 1; }
echo "PASS WS-PLN-PUB-RACE-07/08/09 item-first rollback: publisher waits, then rejects empty publication"

# CASE D — Publisher locks a non-empty draft first but ROLLS BACK; late item insert then succeeds on draft.
cat > "$W/b4.sql" <<SQL
SET lock_timeout='8s';
SET statement_timeout='15s';
BEGIN;
UPDATE student_plan_versions SET status='published', published_at=clock_timestamp() WHERE plan_version_id='$V4';
\! touch "$W/b4_ready"
\! while [ ! -f "$W/b4_go" ]; do sleep 0.05; done
ROLLBACK;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b4.sql" >"$W/b4.log" 2>&1 & PB4=$!
for _ in $(seq 1 200); do [ -f "$W/b4_ready" ] && break; kill -0 "$PB4" 2>/dev/null || { cat "$W/b4.log"; exit 1; }; sleep 0.05; done
[ -f "$W/b4_ready" ] || { echo "FAIL WS-PLN-PUB-RACE-10 publisher did not hold the version lock"; cat "$W/b4.log"; exit 1; }
cat > "$W/a4.sql" <<SQL
SET lock_timeout='8s';
SET statement_timeout='15s';
SET SESSION AUTHORIZATION $WRITER;
BEGIN;
SELECT test_establish('counselor','b7500000-0000-0000-0000-000000000001');
INSERT INTO plan_items(plan_item_id,plan_version_id,plan_id,student_id,item_no,topic_id,planned_local_date,timezone_name,created_by_membership_id)
VALUES ('$ITEM_D2','$V4','a7580000-0000-0000-0000-000000000004','$STU',2,
        'a7570000-0000-0000-0000-000000000001','2026-11-22','Asia/Tehran','b7500000-0000-0000-0000-000000000001');
COMMIT;
RESET SESSION AUTHORIZATION;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a4.sql" >"$W/a4.log" 2>&1 & PA4=$!
BLOCKED=0
for _ in $(seq 1 200); do
  N="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%$ITEM_D2%'")"
  [ "${N:-0}" -ge 1 ] && { BLOCKED=1; break; }
  kill -0 "$PA4" 2>/dev/null || break
  sleep 0.05
done
touch "$W/b4_go"
wait "$PB4"
wait "$PA4"
[ "$BLOCKED" = "1" ] || { echo "FAIL WS-PLN-PUB-RACE-10 item insert did not wait for publisher rollback"; cat "$W/a4.log"; exit 1; }
[ "$(psql -X -tA -d "$DB" -c "SELECT status FROM student_plan_versions WHERE plan_version_id='$V4'")" = "draft" ] || { echo "FAIL WS-PLN-PUB-RACE-11 publisher rollback did not preserve draft"; exit 1; }
[ "$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM plan_items WHERE plan_version_id='$V4'")" = "2" ] || { echo "FAIL WS-PLN-PUB-RACE-11 item insert did not proceed after publication rollback"; exit 1; }
echo "PASS WS-PLN-PUB-RACE-10/11 publisher-first rollback: item waits, then succeeds on the restored draft"
echo "PLAN VERSION PUBLICATION / ITEM INSERT RACE COMPLETED"
