#!/usr/bin/env bash
# Concurrency tests RR-01 (same assertion registered twice) and RR-02 (same receipt, same idempotency
# key, consumed by two adapter sessions). Synthetic data only. Requires the full bootstrap order on <db>.
# Usage (superuser OS account): bash receipt_20_race.sh <db> <workspace_key> <dir_with_session_sql>
set -u
DB="$1"; K="$2"; DIR="$3"; W="$(mktemp -d)"; fail=0
ADAPTER="ws_${K}_governance_adapter_rt"; VERIFIER="ws_${K}_verifier_rt"
P="psql -X -v ON_ERROR_STOP=1 -q -d $DB"

# ---- RR-01: two verifier sessions register the SAME assertion_id with different receipt ids ----
reg(){ cat > "$W/reg_$1.sql" <<SQL
SET SESSION AUTHORIZATION "$VERIFIER";
SELECT pg_sleep($2);
BEGIN;
INSERT INTO governance_proof_receipts(receipt_id,assertion_id,nonce_digest,issuer_id,audience,key_id,workspace_id,
  actor_membership_id,authn_event_ref,assurance_ref,action,aggregate_type,aggregate_id,target_membership_id,
  role_or_permission_key,scope_digest,authority_ref,policy_version,idempotency_key,payload_digest,canonicalization_version,
  issued_at,not_before,expires_at,verifier_kind,verifier_outcome)
VALUES('$3','f9100000-0000-0000-0000-0000000000a1',sha256(convert_to('rr-nonce-$1','UTF8')),'test-issuer','governance_adapter','k1',
  'a9100000-0000-0000-0000-000000000001','b9100000-0000-0000-0000-000000000001','authn-event-x','assurance-x',
  'role_granted','membership_role','b9100000-0000-0000-0000-000000000003','b9100000-0000-0000-0000-000000000003',
  'counselor',sha256(convert_to('scope-x','UTF8')),'authority-x','policy-v1','rr-key-$1',
  receipt_payload_digest_v1('{"role_key":"counselor"}'::jsonb), 'receipt-canon-v1',
  now()-interval '1 hour', now()-interval '1 minute', now()+interval '1 day',
  'external_independent_verifier','verified');
SELECT pg_sleep(1);
COMMIT;
SQL
  psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/reg_$1.sql" > "$W/reg_$1.log" 2>&1; echo $? > "$W/reg_$1.rc"
}
reg a 0 e9100000-0000-0000-0000-0000000000a1 &
reg b 0.3 e9100000-0000-0000-0000-0000000000b1 &
wait
ra_rc=$(cat "$W/reg_a.rc"); rb_rc=$(cat "$W/reg_b.rc")
echo "RR-01 registration exit A=$ra_rc B=$rb_rc (expected one 0 and one 3)"
# both sessions used the same assertion id; exactly one row may exist
$P -c "SELECT 1" >/dev/null 2>&1
ra=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM governance_proof_receipts WHERE assertion_id='f9100000-0000-0000-0000-0000000000a1'")
echo "RR-01 rows for the assertion = $ra (expected 1)"
loser=$([ "$ra_rc" = 0 ] && cat "$W/reg_b.log" || cat "$W/reg_a.log")
if { [ "$ra_rc" = 0 ] && [ "$rb_rc" = 3 ]; } || { [ "$ra_rc" = 3 ] && [ "$rb_rc" = 0 ]; }; then
  echo "$loser" | grep -q "assertion_id" && [ "$ra" = "1" ] && echo "PASS RR-01 (one winner; loser rejected by the assertion_id unique key)" || { echo "FAIL RR-01 (loser reason)"; fail=1; }
else echo "FAIL RR-01 (exit codes)"; fail=1; fi

# ---- RR-02: same receipt, same idempotency key, two concurrent adapter sessions ----
RID=$(psql -X -tA -d "$DB" -c "SELECT receipt_id FROM governance_proof_receipts WHERE assertion_id='f9100000-0000-0000-0000-0000000000a1' LIMIT 1")
KEY=$(psql -X -tA -d "$DB" -c "SELECT idempotency_key FROM governance_proof_receipts WHERE receipt_id='$RID'")
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -v tag=A -v receipt="$RID" -v key="$KEY" -v event=d9100000-0000-0000-0000-0000000000c1 \
  -v sleep_before=0 -v hold=2 -v ws_adapter="$ADAPTER" -f "$DIR/receipt_session_consume.sql" > "$W/c_a.log" 2>&1 & pa=$!
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -v tag=B -v receipt="$RID" -v key="$KEY" -v event=d9100000-0000-0000-0000-0000000000c2 \
  -v sleep_before=0.5 -v hold=0 -v ws_adapter="$ADAPTER" -f "$DIR/receipt_session_consume.sql" > "$W/c_b.log" 2>&1 & pb=$!
wait $pa; ea=$?; wait $pb; eb=$?
events=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM workspace_governance_events WHERE idempotency_key='$KEY'")
ida=$(grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}' "$W/c_a.log" | head -1); idb=$(grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}' "$W/c_b.log" | head -1)
echo "RR-02 exit A=$ea B=$eb ; events for key=$events (expected 1) ; returned event A=$ida B=$idb"
if [ "$ea" = 0 ] && [ "$eb" = 0 ] && [ "$events" = 1 ] && [ "$ida" = "$idb" ] && [ -n "$ida" ]; then
  echo "PASS RR-02 (exactly one effect; both sessions return the original event)"
else echo "FAIL RR-02"; cat "$W/c_b.log" | tail -3; fail=1; fi
# ---- RR-03: two concurrent IDENTICAL retries of an already consumed receipt ----
# Both must return the original event; the event count must not change (no second effect).
before=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM workspace_governance_events WHERE idempotency_key='$KEY'")
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -v tag=C -v receipt="$RID" -v key="$KEY" -v event=d9100000-0000-0000-0000-0000000000c3 \
  -v sleep_before=0 -v hold=1 -v ws_adapter="$ADAPTER" -f "$DIR/receipt_session_consume.sql" > "$W/r3_c.log" 2>&1 & p3c=$!
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -v tag=D -v receipt="$RID" -v key="$KEY" -v event=d9100000-0000-0000-0000-0000000000c4 \
  -v sleep_before=0.2 -v hold=0 -v ws_adapter="$ADAPTER" -f "$DIR/receipt_session_consume.sql" > "$W/r3_d.log" 2>&1 & p3d=$!
wait $p3c; e3c=$?; wait $p3d; e3d=$?
after=$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM workspace_governance_events WHERE idempotency_key='$KEY'")
i3c=$(grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}' "$W/r3_c.log" | head -1); i3d=$(grep -oE '[0-9a-f]{8}-[0-9a-f-]{27}' "$W/r3_d.log" | head -1)
echo "RR-03 exit C=$e3c D=$e3d ; events before=$before after=$after ; returned C=$i3c D=$i3d (original=$ida)"
if [ "$e3c" = 0 ] && [ "$e3d" = 0 ] && [ "$before" = "$after" ] && [ "$i3c" = "$ida" ] && [ "$i3d" = "$ida" ]; then
  echo "PASS RR-03 (concurrent retries of a consumed receipt return the original event; no second effect)"
else echo "FAIL RR-03"; fail=1; fi

rm -rf "$W"
exit $fail
