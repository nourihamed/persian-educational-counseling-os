#!/usr/bin/env bash
# Two concurrent claims for the same canonical mobile+grade in DIFFERENT Workspaces.
# Usage (superuser OS account), on a fresh DB where cp_01 is applied and fixtures exist:
#   bash cp_20_race.sh <dbname>
set -u; DB="$1"; W="$(mktemp -d)"
cat > "$W/a.sql" <<'SQL'
BEGIN; INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
VALUES (gen_random_uuid(),'b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','grade_12',1,decode(repeat('44',32),'hex'),'active',1);
SELECT pg_sleep(2); COMMIT;
SQL
cat > "$W/b.sql" <<'SQL'
SELECT pg_sleep(0.5); BEGIN;
INSERT INTO enrollment_claims (claim_id,student_id,workspace_id,grade_key,key_version,mobile_hmac,claim_state,ownership_generation)
VALUES (gen_random_uuid(),'b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','grade_12',1,decode(repeat('44',32),'hex'),'active',1);
COMMIT;
SQL
# Fresh students with NO claim, so the race exercises only the GLOBAL identity rule.
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c "
INSERT INTO platform_students (student_id) VALUES ('b0000000-0000-0000-0000-0000000000a1'),('b0000000-0000-0000-0000-0000000000a2');
INSERT INTO student_ownership (student_id, owner_workspace_id, ownership_generation, lifecycle_state) VALUES
 ('b0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001',1,'active'),
 ('b0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000003',1,'active');" || { echo "fixture failed"; exit 2; }
sed -i "s/b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000003','grade_12'/b0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000003','grade_12'/" "$W/a.sql"
sed -i "s/b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','grade_12'/b0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','grade_12'/" "$W/b.sql"
chmod -R a+r "$W"
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a.sql" >"$W/a.log" 2>&1 & pa=$!
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!
wait $pa; ea=$?; wait $pb; eb=$?
n=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM enrollment_claims WHERE mobile_hmac=decode(repeat('44',32),'hex') AND grade_key='grade_12' AND claim_state='active'")
echo "exit A=$ea B=$eb ; active claims for the identity=$n (expected 1)"
echo "B error: $(grep -m1 ERROR "$W/b.log" | sed 's/.*ERROR:  //')"
if [ "$ea" = 0 ] && [ "$eb" = 3 ] && [ "$n" = 1 ] && grep -q enrollment_claims_global_identity "$W/b.log"; then echo "PASS CP-RACE-01"; rm -rf "$W"; exit 0; fi
echo "FAIL CP-RACE-01"; echo "(kept: $W)"; exit 1
