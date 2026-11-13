#!/usr/bin/env bash
# ASM-RACE-01: a response change racing with submission (synthetic). Run on a database where
# workspace_schema_tests.sql and workspace_assessment_guardian_tests.sql already ran (reuses their fixtures).
# Session A changes response 2 from correct to wrong and holds its transaction open.
# Session B submits with counters (2,0,0) computed BEFORE A's change. B must wait for A and then be rejected,
# because the stored responses are (1,1,0). Without the attempt row lock B would commit stale counters.
# Usage: bash workspace_assessment_submit_race.sh <db>
set -u
DB="$1"; W="$(mktemp -d)"; AT=e4000000-0000-0000-0000-0000000000a1
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<SQL || { echo "FAIL ASM-RACE-01 fixture"; exit 2; }
INSERT INTO test_definition_versions(version_id,test_id,version_no,question_count,scoring_policy_snapshot)
VALUES ('d4100000-0000-0000-0000-0000000000a1','d4000000-0000-0000-0000-000000000001',7,2,'{"version":"race"}'::jsonb);
INSERT INTO test_definition_version_questions(version_question_id,version_id,question_no,item_ref)
SELECT ('d4290000-0000-0000-0000-0000000000a'||g)::uuid,'d4100000-0000-0000-0000-0000000000a1',g,'race-item-'||g
  FROM generate_series(1,2) g;
UPDATE test_definition_versions SET status='published', published_at=now() WHERE version_id='d4100000-0000-0000-0000-0000000000a1';
INSERT INTO test_attempts(attempt_id,test_id,definition_version_id,student_id,started_at,question_count,scoring_policy_snapshot)
VALUES ('$AT','d4000000-0000-0000-0000-000000000001','d4100000-0000-0000-0000-0000000000a1','e1000000-0000-0000-0000-000000000001',now(),2,'{"version":"race"}'::jsonb);
INSERT INTO test_responses(response_id,attempt_id,definition_version_id,version_question_id,question_no,response_state)
SELECT gen_random_uuid(),'$AT','d4100000-0000-0000-0000-0000000000a1',q.version_question_id,q.question_no,'correct'
  FROM test_definition_version_questions q WHERE q.version_id='d4100000-0000-0000-0000-0000000000a1';
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c "BEGIN; UPDATE test_responses SET response_state='wrong' WHERE attempt_id='$AT' AND question_no=2; SELECT pg_sleep(2); COMMIT;" >"$W/a.log" 2>&1 & pa=$!
sleep 0.6
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c "SELECT submit_test_attempt('$AT',2,0,0,100,'race-key',sha256('race'::bytea));" >"$W/b.log" 2>&1 & pb=$!
wait $pa; ea=$?; wait $pb; eb=$?
st=$(psql -X -tA -d "$DB" -c "SELECT state FROM test_attempts WHERE attempt_id='$AT'")
resp=$(psql -X -tA -d "$DB" -c "SELECT string_agg(response_state, ',' ORDER BY question_no) FROM test_responses WHERE attempt_id='$AT'")
echo "ASM-RACE-01 exit A=$ea B=$eb ; attempt state=$st ; responses=$resp ; B: $(grep -m1 ERROR "$W/b.log" | sed 's/.*ERROR:  //' | cut -c1-110)"
if [ "$ea" = 0 ] && [ "$eb" != 0 ] && [ "$st" = started ] && [ "$resp" = "correct,wrong" ] && grep -q "differ from responses" "$W/b.log"; then
  echo "PASS ASM-RACE-01 (stale submission rejected after waiting; attempt stays started)"; rm -rf "$W"; exit 0
fi
echo "FAIL ASM-RACE-01"; cat "$W/b.log" | tail -3; exit 1
