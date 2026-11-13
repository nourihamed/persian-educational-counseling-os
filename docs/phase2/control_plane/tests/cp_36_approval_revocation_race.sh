#!/usr/bin/env bash
# APR-RACE-01: revocation racing with the ownership switch (synthetic). Run after cp_35 on the same database.
# Session A records a revocation of the guardian consent and holds its transaction open.
# Session B calls the ownership switch. B must wait for A (both lock the transfer case row) and then be rejected
# with "2 of 3": the revocation committed first, so the approval is not valid at cutover.
# Afterwards a replacement approval is recorded and the switch succeeds (generation 3).
# Usage: bash cp_36_approval_revocation_race.sh <db>
set -u
DB="$1"; W="$(mktemp -d)"; CASE=d0000000-0000-0000-0000-0000000000a4; ST=b0000000-0000-0000-0000-000000000001
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c "BEGIN; INSERT INTO transfer_approval_revocations(revocation_id,approval_id,actor_ref,authn_event_ref,reason_code) VALUES (gen_random_uuid(),'e0000000-0000-0000-0000-000000000041','subject-g4','authn-g4-revoke','synthetic_reason'); SELECT pg_sleep(2); COMMIT;" >"$W/a.log" 2>&1 & pa=$!
sleep 0.6
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c "SELECT switch_student_ownership('$CASE');" >"$W/b.log" 2>&1 & pb=$!
wait $pa; ea=$?; wait $pb; eb=$?
owner=$(psql -X -tA -d "$DB" -c "SELECT owner_workspace_id||' gen '||ownership_generation FROM student_ownership WHERE student_id='$ST'")
echo "APR-RACE-01 exit A=$ea B=$eb ; owner=$owner ; B: $(grep -m1 ERROR "$W/b.log" | sed 's/.*ERROR:  //' | cut -c1-90)"
if [ "$ea" = 0 ] && [ "$eb" != 0 ] && grep -q "2 of 3" "$W/b.log" && [ "$owner" = "a0000000-0000-0000-0000-000000000002 gen 2" ]; then
  echo "PASS APR-RACE-01 (switch waited for the revocation and was rejected; ownership unchanged)"
else echo "FAIL APR-RACE-01"; tail -3 "$W/b.log"; exit 1; fi
out=$(psql -X -v ON_ERROR_STOP=1 -tA -d "$DB" -c "SELECT ax_approval(gen_random_uuid(),'$CASE','guardian_consent','g4-replacement');" -c "SELECT switch_student_ownership('$CASE');" 2>&1); rc=$?
owner=$(psql -X -tA -d "$DB" -c "SELECT owner_workspace_id||' gen '||ownership_generation FROM student_ownership WHERE student_id='$ST'")
hist=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM transfer_approvals WHERE case_id='$CASE'")
echo "APR-SWITCH-01 exit=$rc ; owner=$owner ; approval events kept for the case=$hist"
if [ $rc = 0 ] && [ "$owner" = "a0000000-0000-0000-0000-000000000003 gen 3" ] && [ "$hist" = 7 ]; then
  echo "PASS APR-SWITCH-01 (switch succeeds with three current approvals; all 7 historical approval events preserved)"; rm -rf "$W"; exit 0
fi
echo "FAIL APR-SWITCH-01"; echo "$out" | tail -3; exit 1
