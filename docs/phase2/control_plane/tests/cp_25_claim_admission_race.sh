#!/usr/bin/env bash
# Concurrent initial claims for the same canonical mobile+grade must yield one winner.
# Run after cp_01, cp_05, cp_07 and cp_06, with active key 1 and retiring key 2 present.
# Usage: bash cp_25_claim_admission_race.sh <dbname>
set -u
DB="${1:?usage: cp_25_claim_admission_race.sh <dbname>}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL'
INSERT INTO workspaces(workspace_id,workspace_type,status) VALUES
 ('a7300000-0000-0000-0000-000000000001','organization','active'),
 ('a7300000-0000-0000-0000-000000000002','independent_counselor','active');
SQL
if [ "$?" -ne 0 ]; then echo "FAIL CP-ADMIT-RACE fixture setup"; exit 2; fi

cat > "$W/a.sql" <<'SQL'
BEGIN;
SELECT admit_student_identity_claim(
 'race-admit-a',decode(repeat('aa',32),'hex'),
 'b7300000-0000-0000-0000-000000000001','c7300000-0000-0000-0000-000000000001',
 'a7300000-0000-0000-0000-000000000001','grade_10',
 decode('a1','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"3333333333333333333333333333333333333333333333333333333333333333"},{"key_version":2,"mobile_hmac_hex":"4444444444444444444444444444444444444444444444444444444444444444"}]'::jsonb);
SELECT pg_sleep(2);
COMMIT;
SQL

cat > "$W/b.sql" <<'SQL'
SELECT pg_sleep(0.4);
BEGIN;
SELECT admit_student_identity_claim(
 'race-admit-b',decode(repeat('bb',32),'hex'),
 'b7300000-0000-0000-0000-000000000002','c7300000-0000-0000-0000-000000000002',
 'a7300000-0000-0000-0000-000000000002','grade_10',
 decode('b2','hex'),1,
 '[{"key_version":1,"mobile_hmac_hex":"3333333333333333333333333333333333333333333333333333333333333333"},{"key_version":2,"mobile_hmac_hex":"4444444444444444444444444444444444444444444444444444444444444444"}]'::jsonb);
COMMIT;
SQL

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a.sql" >"$W/a.log" 2>&1 & pa=$!
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!
wait "$pa"; ea=$?
wait "$pb"; eb=$?

claims="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM enrollment_claim_identity_aliases WHERE key_version=1 AND mobile_hmac=decode(repeat('33',32),'hex') AND grade_key='grade_10' AND claim_state='active'")"
students="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM platform_students WHERE student_id IN ('b7300000-0000-0000-0000-000000000001','b7300000-0000-0000-0000-000000000002')")"
owners="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM student_ownership WHERE student_id IN ('b7300000-0000-0000-0000-000000000001','b7300000-0000-0000-0000-000000000002')")"
commands="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM identity_admission_commands WHERE idempotency_key IN ('race-admit-a','race-admit-b')")"

echo "exit A=$ea B=$eb; matching active aliases=$claims; students=$students; owners=$owners; admission commands=$commands"
echo "B error: $(grep -m1 'ERROR:' "$W/b.log" | sed 's/.*ERROR:  //')"
if [ "$ea" -eq 0 ] && [ "$eb" -eq 3 ] && [ "$claims" = "1" ] \
   && [ "$students" = "1" ] && [ "$owners" = "1" ] && [ "$commands" = "1" ] \
   && grep -q 'enrollment_claims_global_identity' "$W/b.log"; then
  echo "PASS CP-ADMIT-RACE-01 one global identity winner; losing admission fully rolled back"
  exit 0
fi

echo "FAIL CP-ADMIT-RACE-01"
echo "--- session A ---"; cat "$W/a.log"
echo "--- session B ---"; cat "$W/b.log"
exit 1
