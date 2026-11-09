#!/usr/bin/env bash
# Concurrent global identity claim test. Run on a fresh DB after cp_01, cp_05, cp_02, cp_03 and cp_04.
# Workspace IDs below must already exist; key version 1 is inserted if absent.
set -u
DB="${1:?usage: cp_20_race.sh <dbname>}"
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL'
INSERT INTO mobile_encryption_key_versions(key_version,state,key_manager_ref) VALUES (1,'active','kms://synthetic/mobile-key-v1')
ON CONFLICT (key_version) DO NOTHING;
INSERT INTO mobile_hmac_key_versions(key_version,state) VALUES (1,'active')
ON CONFLICT (key_version) DO NOTHING;
INSERT INTO platform_students(student_id) VALUES
 ('b0000000-0000-0000-0000-0000000000a1'),('b0000000-0000-0000-0000-0000000000a2')
ON CONFLICT DO NOTHING;
INSERT INTO student_ownership(student_id,owner_workspace_id,ownership_generation,lifecycle_state) VALUES
 ('b0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001',1,'active'),
 ('b0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000003',1,'active')
ON CONFLICT DO NOTHING;
INSERT INTO student_contact_index(student_id,key_version,mobile_hmac,mobile_ciphertext,cipher_key_version) VALUES
 ('b0000000-0000-0000-0000-0000000000a1',1,decode(repeat('44',32),'hex'),decode('a1','hex'),1),
 ('b0000000-0000-0000-0000-0000000000a2',1,decode(repeat('44',32),'hex'),decode('a2','hex'),1)
ON CONFLICT (student_id,key_version) DO NOTHING;
SQL
cat > "$W/a.sql" <<'SQL'
BEGIN;
INSERT INTO enrollment_claims(claim_id,student_id,workspace_id,grade_key,claim_state,ownership_generation)
VALUES ('c0000000-0000-0000-0000-0000000000a1','b0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','grade_12','active',1);
INSERT INTO enrollment_claim_identity_aliases(claim_id,grade_key,key_version,mobile_hmac,claim_state)
VALUES ('c0000000-0000-0000-0000-0000000000a1','grade_12',1,decode(repeat('44',32),'hex'),'active');
SELECT pg_sleep(2);
COMMIT;
SQL
cat > "$W/b.sql" <<'SQL'
SELECT pg_sleep(0.5);
BEGIN;
INSERT INTO enrollment_claims(claim_id,student_id,workspace_id,grade_key,claim_state,ownership_generation)
VALUES ('c0000000-0000-0000-0000-0000000000a2','b0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000003','grade_12','active',1);
INSERT INTO enrollment_claim_identity_aliases(claim_id,grade_key,key_version,mobile_hmac,claim_state)
VALUES ('c0000000-0000-0000-0000-0000000000a2','grade_12',1,decode(repeat('44',32),'hex'),'active');
COMMIT;
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a.sql" >"$W/a.log" 2>&1 & pa=$!
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!
wait "$pa"; ea=$?
wait "$pb"; eb=$?
n=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM enrollment_claim_identity_aliases WHERE key_version=1 AND mobile_hmac=decode(repeat('44',32),'hex') AND grade_key='grade_12' AND claim_state='active'")
echo "exit A=$ea B=$eb; matching active aliases=$n (expected 1)"
if [ "$ea" -eq 0 ] && [ "$eb" -eq 3 ] && [ "$n" -eq 1 ] && grep -q enrollment_claims_global_identity "$W/b.log"; then
  echo "PASS CP-RACE-01"; exit 0
fi
echo "FAIL CP-RACE-01"
cat "$W/a.log" "$W/b.log"
exit 1
