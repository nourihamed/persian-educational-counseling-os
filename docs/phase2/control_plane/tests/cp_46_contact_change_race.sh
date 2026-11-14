#!/usr/bin/env bash
# CC-RACE-01: two students in the same grade, in different Workspaces, change to the SAME number concurrently.
# Exactly one may win (global mobile+grade identity). Synthetic only. Run after cp_40 on the same database.
# Usage: bash cp_46_contact_change_race.sh <db>
set -u
DB="$1"; W="$(mktemp -d)"
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL' || { echo "FAIL CC-RACE-01 fixture"; exit 2; }
SELECT cc_proof('d8000000-0000-0000-0000-0000000000a1','b8000000-0000-0000-0000-000000000001','a8000000-0000-0000-0000-000000000001',1,'88');
SELECT cc_proof('d8000000-0000-0000-0000-0000000000a2','b8000000-0000-0000-0000-000000000002','a8000000-0000-0000-0000-000000000002',1,'88');
SQL
call(){ echo "SET SESSION AUTHORIZATION cp_contact_change_executor; BEGIN; SELECT cc_call('race-$1','race-$1','$2','$3',1,'$4','88'); SELECT pg_sleep($5); COMMIT;"; }
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c "$(call a b8000000-0000-0000-0000-000000000001 a8000000-0000-0000-0000-000000000001 d8000000-0000-0000-0000-0000000000a1 2)" >"$W/a.log" 2>&1 & pa=$!
sleep 0.6
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c "$(call b b8000000-0000-0000-0000-000000000002 a8000000-0000-0000-0000-000000000002 d8000000-0000-0000-0000-0000000000a2 0)" >"$W/b.log" 2>&1 & pb=$!
wait $pa; ea=$?; wait $pb; eb=$?
holders=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM enrollment_claim_identity_aliases WHERE key_version=1 AND grade_key='grade_10' AND claim_state='active' AND encode(mobile_hmac,'hex')=repeat('88',32)")
loser_proof=$(psql -X -tA -d "$DB" -c "SELECT status FROM contact_change_proofs WHERE proof_id='d8000000-0000-0000-0000-0000000000a2'")
audits=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM student_contact_change_audit WHERE idempotency_key LIKE 'race-%'")
echo "CC-RACE-01 exit A=$ea B=$eb ; holders of the number=$holders ; loser proof=$loser_proof ; audit rows=$audits ; B: $(grep -m1 ERROR "$W/b.log" | sed 's/.*ERROR:  //' | cut -c1-90)"
if [ "$ea" = 0 ] && [ "$eb" != 0 ] && [ "$holders" = 1 ] && [ "$loser_proof" = registered ] && [ "$audits" = 1 ] && grep -q enrollment_claims_global_identity "$W/b.log"; then
  echo "PASS CC-RACE-01 (one winner; loser rejected by the global identity index and fully rolled back)"; rm -rf "$W"; exit 0
fi
echo "FAIL CC-RACE-01"; tail -3 "$W/b.log"; exit 1
