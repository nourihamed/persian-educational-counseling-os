#!/usr/bin/env bash
# WS-ISO-01 decision B — REPLAY UNDER CONCURRENCY. Two sessions present the SAME signed assertion at the same
# time. Exactly one may establish a principal; the other must be refused as a replay, never both.
# Coordination is deterministic: session A establishes and holds its transaction open until the driver has
# OBSERVED session B blocked on A's uncommitted nonce; then A commits and B fails on the unique nonce.
# Sensitivity (measured): with the nonce primary key dropped, B does not block and both succeed.
# Synthetic only (D-014). Usage: bash workspace_principal_assertion_race.sh <db> <workspace-key> [nopk]
set -u
DB="${1:?database}"; KEY="${2:?key}"; MODE="${3:-}"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
RL="ws_${KEY}_runtime_login"
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" <<'SQL' || { echo "FAIL ISO-P-RACE fixture"; exit 2; }
INSERT INTO principal_assertion_keys(key_id, algorithm, key_material, max_lifetime)
VALUES ('synthetic-test-iso-race', 'hmac-sha256-synthetic-test',
        ext_crypto.digest('WS-ISO-01 synthetic race key - public, not a secret', 'sha256'), interval '5 minutes')
ON CONFLICT (key_id) DO NOTHING;
UPDATE principal_verification_config SET mode = 'synthetic_test';
UPDATE workspace_memberships SET status='active' WHERE membership_id='b5000000-0000-0000-0000-00000000000b';
CREATE TABLE IF NOT EXISTS iso_race_signal(name text PRIMARY KEY);
GRANT SELECT ON iso_race_signal TO PUBLIC;
SQL
if [ "$MODE" = "nopk" ]; then
  psql -X -q -d "$DB" -c "ALTER TABLE verified_principal_context DROP CONSTRAINT verified_principal_context_nonce_fkey; ALTER TABLE principal_assertion_nonces DROP CONSTRAINT principal_assertion_nonces_pkey" >/dev/null
  echo "NEGATIVE CONTROL: nonce primary key dropped"
fi
read -r A S <<<"$(psql -X -tA -F ' ' -d "$DB" -c "
  WITH l AS (SELECT format('wsp1;a5000000-0000-0000-0000-000000000001;counselor;b5000000-0000-0000-0000-00000000000b;%s;%s;%s;synthetic-test-iso-race',
                           extract(epoch FROM clock_timestamp())::bigint - 5, extract(epoch FROM clock_timestamp())::bigint + 120,
                           encode(ext_crypto.gen_random_bytes(16),'hex')) AS a)
  SELECT a, encode(ext_crypto.hmac(convert_to(a,'UTF8'), (SELECT key_material FROM principal_assertion_keys WHERE key_id='synthetic-test-iso-race'), 'sha256'),'hex') FROM l")"
cat > "$W/a.sql" <<SQL
SET SESSION AUTHORIZATION $RL;
BEGIN;
SELECT establish_principal('$A','$S');
DO \$\$ BEGIN
  FOR i IN 1..1200 LOOP
    EXIT WHEN EXISTS (SELECT 1 FROM public.iso_race_signal WHERE name='go');
    PERFORM pg_sleep(0.05);
  END LOOP;
END \$\$;
COMMIT;
SQL
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$W/a.sql" >"$W/a.log" 2>&1 & pa=$!
held=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND query LIKE '%iso_race_signal%' AND state='active'")"
  [ "${n:-0}" -ge 1 ] && { held=1; break; }
  kill -0 "$pa" 2>/dev/null || break; sleep 0.05
done
[ "$held" = "1" ] || { echo "FAIL ISO-P-RACE-01 session A never reached its wait"; cat "$W/a.log"; exit 2; }
cat > "$W/b.sql" <<SQL
SET SESSION AUTHORIZATION $RL;
BEGIN;
SELECT establish_principal('$A','$S') AS race_b;
COMMIT;
SQL
psql -X -q -v ON_ERROR_STOP=1 -d "$DB" -f "$W/b.sql" >"$W/b.log" 2>&1 & pb=$!
blocked=0
for _ in $(seq 1 200); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%race_b%'")"
  [ "${n:-0}" -ge 1 ] && { blocked=1; break; }
  kill -0 "$pb" 2>/dev/null || break; sleep 0.05
done
psql -X -q -d "$DB" -c "INSERT INTO iso_race_signal(name) VALUES('go')" >/dev/null
wait "$pa"; ea=$?; wait "$pb"; eb=$?
nonces="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM principal_assertion_nonces WHERE key_id='synthetic-test-iso-race'")"
psql -X -q -d "$DB" -c "UPDATE principal_verification_config SET mode='disabled'; DROP TABLE iso_race_signal" >/dev/null
echo "A exit=$ea  B exit=$eb  nonces recorded=$nonces"
ok=1
if [ "$blocked" = "1" ]; then echo "PASS ISO-P-RACE-01 the second presentation BLOCKED on the first one's uncommitted nonce"
else echo "FAIL ISO-P-RACE-01 the second presentation did not block"; ok=0; fi
if [ "$ea" -eq 0 ] && [ "$eb" -ne 0 ] && grep -q "replayed" "$W/b.log"; then
  echo "PASS ISO-P-RACE-02 exactly one presentation established a principal; the other was refused as a replay"
else echo "FAIL ISO-P-RACE-02 expected A to succeed and B to be refused as replayed; B said: $(grep -m1 ERROR "$W/b.log")"; ok=0; fi
if [ "$nonces" = "1" ]; then echo "PASS ISO-P-RACE-03 the nonce was consumed exactly once"
else echo "FAIL ISO-P-RACE-03 nonce consumed $nonces times"; ok=0; fi
[ "$ok" = "1" ] || exit 1
echo "PRINCIPAL ASSERTION RACE COMPLETED"
