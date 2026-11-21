#!/usr/bin/env bash
# Batch 7 — CONTACT IDENTITY CONCURRENCY. Two races the Supervisor brief lists as NOT RUN:
#   A. concurrent contact change and HMAC key rotation
#   B. concurrent contact change and ownership transfer
#
# Both serializations are DESIGNED IN and were documented in comments, and neither had ever been executed.
# `change_student_mobile_contact()` takes `FOR SHARE` on identity_write_gate (step 1) and a lock on the
# ownership row (step 2); rotation takes `FOR UPDATE` on the same gate row, and the ownership switch takes
# the same ownership row. A comment claiming mutual exclusion is not evidence of it, which is the whole
# point of this file.
#
# WHY IT MATTERS
#   A. If a contact change could land mid-rotation, an identity alias would be written at a key version the
#      rotation is retiring, and the deferred coverage check that guarantees every claim has an alias at
#      every live key version would be evaluated against a set that changed underneath it. Contact lookup
#      is how a student is found at all, so a hole here is a lookup that silently fails or resolves wrongly.
#   B. If a contact change could land during an ownership switch, the contact identity would be written
#      against an owner and generation that no longer hold — the same stale-owner class as the transfer
#      fence, but on the globally unique contact index rather than Workspace-local data.
#
# COORDINATION IS DETERMINISTIC, NOT TIMING-BASED. The first session opens a transaction, performs its
# work, and then waits for an explicit go signal. The driver sends that signal only after it has OBSERVED
# the second session blocked on a lock in pg_stat_activity. The outcome cannot depend on scheduling: either
# the second session blocks or the test fails. The existing cp_46_contact_change_race.sh uses `sleep 0.6`
# plus `pg_sleep 2` to order its sessions; this file does not.
#
# The first session is always SIGNALLED to commit, never killed: terminating it would ABORT its
# transaction, release every lock and let the second session succeed legitimately — which is not the case
# under test. Two earlier race scripts in this project were written that way and produced misleading passes.
#
# SENSITIVITY, MEASURED (recorded in docs/phase2/IMPLEMENTATION_RESPONSE_2026-11-14.md section 13):
#   removing the `FOR SHARE` gate read from step 1 of change_student_mobile_contact() makes race A's
#   CID-RACE-A1 fail, because rotation then proceeds while the contact change is in flight.
#
# EACH RACE RUNS IN ITS OWN FRESH DATABASE, and that is not fastidiousness. Race A completes an HMAC
# rotation, which leaves key version 1 `retiring` and 2 `active` and advances the gate's rotation epoch;
# race A's switch also moves a student's ownership generation. Running race B in the same database made its
# contact change abort on preconditions that race A had changed, the locks were released early, and the
# switch then ran unblocked — which looked exactly like a missing lock in the implementation. It was not:
# `change_student_mobile_contact()` does take `FOR UPDATE` on student_ownership. The test was at fault, and
# the fix is isolation rather than a weaker assertion.
#
# Run after cp_40_contact_change_tests.sql in the same database: it provides the Workspaces, key versions,
# students and the cc_proof / cc_call / cc_aliases helpers reused here.
# Synthetic only (D-014). Usage: bash cp_48_contact_identity_race.sh <db> <a|b>
set -u
DB="${1:?database name required}"
MODE="${2:?mode required: a (rotation) or b (ownership switch)}"
case "$MODE" in a|b) : ;; *) echo "FAIL unknown mode '$MODE' (expected a or b)"; exit 2 ;; esac
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT

psql -X -v ON_ERROR_STOP=1 -q -d "$DB" <<'SQL' || { echo "FAIL CID-RACE fixture setup"; exit 2; }
-- Scratch coordination table: no contact, identity or ownership column, so no guard applies to it.
CREATE TABLE cid_race_signal(name text PRIMARY KEY);
GRANT SELECT, INSERT ON cid_race_signal TO PUBLIC;
SELECT cc_proof('d8000000-0000-0000-0000-0000000000c1','b8000000-0000-0000-0000-000000000001',
                'a8000000-0000-0000-0000-000000000001',1,'c1');
SELECT cc_proof('d8000000-0000-0000-0000-0000000000c2','b8000000-0000-0000-0000-000000000002',
                'a8000000-0000-0000-0000-000000000002',1,'c2');
-- Each proof above is bound to ONE student, Workspace and generation. Using one for another student is
-- refused, which is correct -- and in an earlier version of this file that refusal aborted race B's
-- transaction before any lock mattered, which looked like a missing lock in the implementation.
SQL

fail=0

# =====================================================================================================
# RACE A — contact change in flight, HMAC rotation attempts to begin.
# =====================================================================================================
if [ "$MODE" = "a" ]; then
echo "=== RACE A: contact change in flight, HMAC rotation tries to begin"

cat > "$W/a_contact.sql" <<'SQL'
SET SESSION AUTHORIZATION cp_contact_change_executor;
BEGIN;
SELECT cc_call('cid-a','cid-a','b8000000-0000-0000-0000-000000000001',
               'a8000000-0000-0000-0000-000000000001',1,'d8000000-0000-0000-0000-0000000000c1','c1');
DO $$ BEGIN
  FOR i IN 1..1200 LOOP
    EXIT WHEN EXISTS (SELECT 1 FROM public.cid_race_signal WHERE name='go_a');
    PERFORM pg_sleep(0.05);
  END LOOP;
END $$;
COMMIT;
SQL
psql -X -q -d "$DB" -f "$W/a_contact.sql" >"$W/a_contact.log" 2>&1 & pc=$!

held=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid=l.relation WHERE c.relname='identity_write_gate' AND l.granted AND l.mode='RowShareLock'")"
  if [ "${n:-0}" -ge 1 ]; then held=1; break; fi
  if ! kill -0 "$pc" 2>/dev/null; then break; fi
done
if [ "$held" != "1" ]; then
  echo "FAIL CID-RACE-A1 the contact change never took a SHARE lock on identity_write_gate, so it does not"
  echo "                 serialize against rotation at all"
  kill "$pc" 2>/dev/null; cat "$W/a_contact.log"; exit 1
fi

# Rotation must BLOCK on the gate row the contact change is holding.
cat > "$W/a_rot.sql" <<'SQL'
SET SESSION AUTHORIZATION cp_rotation_executor;
SELECT begin_identity_hmac_rotation();
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/a_rot.sql" >"$W/a_rot.log" 2>&1 & pr=$!

blocked=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%begin_identity_hmac_rotation%'")"
  if [ "${n:-0}" -ge 1 ]; then blocked=1; break; fi
  if ! kill -0 "$pr" 2>/dev/null; then break; fi
done
if [ "$blocked" != "1" ]; then
  echo "FAIL CID-RACE-A1 rotation did NOT block on the in-flight contact change. An identity alias could be"
  echo "                 written at a key version the rotation is retiring."
  cat "$W/a_rot.log"
  psql -X -q -d "$DB" -c "INSERT INTO cid_race_signal(name) VALUES('go_a')" >/dev/null 2>&1
  wait "$pc" 2>/dev/null; wait "$pr" 2>/dev/null; exit 1
fi
echo "observed: begin_identity_hmac_rotation() is blocked on the contact change's gate lock"

psql -X -q -d "$DB" -c "INSERT INTO cid_race_signal(name) VALUES('go_a')" >/dev/null
wait "$pc"; ec=$?
wait "$pr"; er=$?

cc_status="$(psql -X -tA -d "$DB" -c "SELECT status FROM contact_change_proofs WHERE proof_id='d8000000-0000-0000-0000-0000000000c1'")"
maint="$(psql -X -tA -d "$DB" -c "SELECT maintenance_mode FROM identity_write_gate WHERE singleton=true")"
coverage_ok="$(psql -X -tA -d "$DB" -c "SELECT CASE WHEN (SELECT count(*) FROM mobile_hmac_key_versions WHERE state<>'retired')=0 THEN 'n/a' ELSE 'checked' END")"
echo "contact exit=$ec rotation exit=$er proof=$cc_status maintenance_mode=$maint"

[ "$ec" -eq 0 ] || { echo "FAIL CID-RACE-A2 the contact change did not commit"; cat "$W/a_contact.log"; fail=1; }
[ "$er" -eq 0 ] || { echo "FAIL CID-RACE-A2 rotation did not complete after the contact change settled"; cat "$W/a_rot.log"; fail=1; }
[ "$cc_status" = "consumed" ] || { echo "FAIL CID-RACE-A2 the proof is '$cc_status', expected consumed"; fail=1; }
[ "$maint" = "t" ] || { echo "FAIL CID-RACE-A2 rotation did not leave maintenance mode on (got '$maint')"; fail=1; }

# With rotation now holding the gate exclusively, a further contact change must be REFUSED, not queued
# into a half-rotated state. This is the other direction of the same mutual exclusion.
after="$(psql -X -d "$DB" 2>&1 <<'SQL' | tail -3
SET SESSION AUTHORIZATION cp_contact_change_executor;
SELECT cc_call('cid-a2','cid-a2','b8000000-0000-0000-0000-000000000002',
               'a8000000-0000-0000-0000-000000000002',1,'d8000000-0000-0000-0000-0000000000c2','c2');
SQL
)"
case "$after" in
  *"maintenance mode"*) echo "PASS CID-RACE-A3 a contact change during maintenance mode is refused" ;;
  *) echo "FAIL CID-RACE-A3 a contact change was accepted while rotation held the gate: $after"; fail=1 ;;
esac

if [ "$fail" = "0" ]; then
  echo "PASS CID-RACE-A1 rotation blocked on the in-flight contact change instead of proceeding"
  echo "PASS CID-RACE-A2 both committed in order: the contact change landed, then rotation began"
  exit 0
fi
exit 1
fi   # end of mode a

# =====================================================================================================
# RACE B — contact change in flight, ownership switch attempts to run for the same student.
# =====================================================================================================
echo "=== RACE B: contact change in flight, ownership switch for the same student"

# Student 3, untouched by any other suite in this database. Its proof is bound to student 3, its own
# Workspace and its own generation: a proof bound to a different student is refused outright, which is
# correct behaviour and would abort the transaction before any lock mattered.
OWNER="$(psql -X -tA -d "$DB" -c "SELECT owner_workspace_id FROM student_ownership WHERE student_id='b8000000-0000-0000-0000-000000000003'")"
GEN0="$(psql -X -tA -d "$DB" -c "SELECT ownership_generation FROM student_ownership WHERE student_id='b8000000-0000-0000-0000-000000000003'")"
DEST="$(psql -X -tA -d "$DB" -c "SELECT workspace_id FROM workspaces WHERE workspace_id <> '$OWNER' LIMIT 1")"
echo "student 3: owner=$OWNER generation=$GEN0 destination=$DEST"
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" \
  -c "SELECT cc_proof('d8000000-0000-0000-0000-0000000000b3','b8000000-0000-0000-0000-000000000003','$OWNER',$GEN0,'b3');" >/dev/null

# A transfer case for student 1, carried all the way to cutover_frozen with its three approvals, so that
# switch_student_ownership() is genuinely permitted to run. The state progression and approval shape mirror
# cp_45_executor_identity_tests.sql; nothing here weakens a check, it only satisfies the preconditions.
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" >"$W/b_setup.log" 2>&1 <<SQL || { echo "FAIL CID-RACE-B0 setup"; cat "$W/b_setup.log"; exit 2; }
INSERT INTO transfer_cases(case_id,student_id,source_workspace_id,destination_workspace_id,
                           expected_generation,initiator_kind,state,idempotency_key)
VALUES ('d4800000-0000-0000-0000-000000000001','b8000000-0000-0000-0000-000000000003',
        '$OWNER','$DEST', $GEN0,'current_counselor','requested','cid-race-b-case');
UPDATE transfer_cases SET state='approvals_pending' WHERE case_id='d4800000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='approved'          WHERE case_id='d4800000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='preflight_ok'      WHERE case_id='d4800000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staging'           WHERE case_id='d4800000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='staged_verified'   WHERE case_id='d4800000-0000-0000-0000-000000000001';
UPDATE transfer_cases
   SET source_freeze_token='freeze-cid-b', source_frozen_at=now(),
       final_snapshot_ref='snapshot-cid-b', final_snapshot_at=now(),
       snapshot_manifest_hash=decode(repeat('4b',32),'hex'),
       destination_validation_ref='validation-cid-b', destination_validated_at=now()
 WHERE case_id='d4800000-0000-0000-0000-000000000001';
UPDATE transfer_cases SET state='cutover_frozen'    WHERE case_id='d4800000-0000-0000-0000-000000000001';
INSERT INTO transfer_approvals(approval_id,assertion_id,nonce_digest,case_id,approval_kind,evidence_ref,
                               approver_ref,authn_event_ref,authority_snapshot,verified_at)
SELECT gen_random_uuid(),gen_random_uuid(),sha256(convert_to('cid-b-'||k,'UTF8')),
       'd4800000-0000-0000-0000-000000000001',k,'ev-cid-b-'||k,'subject-cid-b-'||k,'authn-cid-b-'||k,
       jsonb_build_object('synthetic',true,'workspace_id',
         CASE k WHEN 'destination_acceptance' THEN c.destination_workspace_id ELSE c.source_workspace_id END),
       now()
  FROM unnest(ARRAY['guardian_consent','fee_confirmation','destination_acceptance']) k,
       transfer_cases c WHERE c.case_id='d4800000-0000-0000-0000-000000000001';
SQL

cat > "$W/b_contact.sql" <<SQL
SET SESSION AUTHORIZATION cp_contact_change_executor;
BEGIN;
SELECT cc_call('cid-b','cid-b','b8000000-0000-0000-0000-000000000003',
               '$OWNER',$GEN0,'d8000000-0000-0000-0000-0000000000b3','b3');
DO \$\$ BEGIN
  FOR i IN 1..1200 LOOP
    EXIT WHEN EXISTS (SELECT 1 FROM public.cid_race_signal WHERE name='go_b');
    PERFORM pg_sleep(0.05);
  END LOOP;
END \$\$;
COMMIT;
SQL
psql -X -q -d "$DB" -f "$W/b_contact.sql" >"$W/b_contact.log" 2>&1 & pcb=$!

held=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid=l.relation WHERE c.relname='student_ownership' AND l.granted AND l.mode IN ('RowShareLock','RowExclusiveLock')")"
  if [ "${n:-0}" -ge 1 ]; then held=1; break; fi
  if ! kill -0 "$pcb" 2>/dev/null; then break; fi
done
if [ "$held" != "1" ]; then
  echo "FAIL CID-RACE-B1 the contact change never locked the student's ownership row, so it does not"
  echo "                 serialize against the ownership switch"
  psql -X -q -d "$DB" -c "INSERT INTO cid_race_signal(name) VALUES('go_b')" >/dev/null 2>&1
  wait "$pcb" 2>/dev/null; cat "$W/b_contact.log"; exit 1
fi
echo "observed: the contact change holds a lock on the student's ownership row"
gen_before="$GEN0"

# The real switch, run concurrently. It must BLOCK on the ownership row the contact change holds.
cat > "$W/b_switch.sql" <<'SQL'
SET SESSION AUTHORIZATION cp_transfer_executor;
SELECT switch_student_ownership('d4800000-0000-0000-0000-000000000001');
SQL
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -f "$W/b_switch.sql" >"$W/b_switch.log" 2>&1 & psw=$!

sw_blocked=0
for _ in $(seq 1 400); do
  n="$(psql -X -tA -d "$DB" -c "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND wait_event_type='Lock' AND query LIKE '%switch_student_ownership%'")"
  if [ "${n:-0}" -ge 1 ]; then sw_blocked=1; break; fi
  if ! kill -0 "$psw" 2>/dev/null; then break; fi
done
if [ "$sw_blocked" != "1" ]; then
  echo "FAIL CID-RACE-B1 the ownership switch did NOT block on the in-flight contact change. A contact"
  echo "                 identity could be written against an owner and generation that no longer hold."
  cat "$W/b_switch.log"
  psql -X -q -d "$DB" -c "INSERT INTO cid_race_signal(name) VALUES('go_b')" >/dev/null 2>&1
  wait "$pcb" 2>/dev/null; wait "$psw" 2>/dev/null; exit 1
fi
echo "observed: switch_student_ownership() is blocked on the contact change's ownership-row lock"

psql -X -q -d "$DB" -c "INSERT INTO cid_race_signal(name) VALUES('go_b')" >/dev/null
wait "$pcb"; ecb=$?
wait "$psw"; esw=$?

gen="$(psql -X -tA -d "$DB" -c "SELECT ownership_generation FROM student_ownership WHERE student_id='b8000000-0000-0000-0000-000000000003'")"
owner="$(psql -X -tA -d "$DB" -c "SELECT owner_workspace_id FROM student_ownership WHERE student_id='b8000000-0000-0000-0000-000000000003'")"
case_state="$(psql -X -tA -d "$DB" -c "SELECT state FROM transfer_cases WHERE case_id='d4800000-0000-0000-0000-000000000001'")"
cc_b="$(psql -X -tA -d "$DB" -c "SELECT status FROM contact_change_proofs WHERE proof_id='d8000000-0000-0000-0000-0000000000b3'")"
echo "contact exit=$ecb switch exit=$esw generation $gen_before -> $gen  owner=$owner  case=$case_state  proof=$cc_b"

[ "$ecb" -eq 0 ] || { echo "FAIL CID-RACE-B2 the contact change did not commit"; cat "$W/b_contact.log"; fail=1; }
[ "$esw" -eq 0 ] || { echo "FAIL CID-RACE-B2 the switch did not complete after the contact change settled"; cat "$W/b_switch.log"; fail=1; }
if [ -n "$gen_before" ] && [ -n "$gen" ] && [ "$gen" -le "$gen_before" ]; then
  echo "FAIL CID-RACE-B2 the ownership generation did not advance ($gen_before -> $gen)"; fail=1
fi
[ "$owner" = "$DEST" ] || { echo "FAIL CID-RACE-B2 ownership did not move to the destination (owner=$owner, expected $DEST)"; fail=1; }
[ "$cc_b" = "consumed" ] || { echo "FAIL CID-RACE-B2 the contact proof is '$cc_b', expected consumed"; fail=1; }

# The switch has now advanced the generation, so a contact change citing the OLD generation must be
# refused. This is the property the ownership-row lock exists to protect: an identity write may never land
# against an owner or generation that no longer holds. Before the fix to the ordering this would be the
# window in which it could.
psql -X -v ON_ERROR_STOP=1 -q -d "$DB" -c \
  "SELECT cc_proof('d8000000-0000-0000-0000-0000000000c3','b8000000-0000-0000-0000-000000000003','$OWNER',$gen_before,'c3');" >/dev/null
stale="$(psql -X -d "$DB" 2>&1 <<SQL | tail -3
SET SESSION AUTHORIZATION cp_contact_change_executor;
SELECT cc_call('cid-b-stale','cid-b-stale','b8000000-0000-0000-0000-000000000003',
               '$OWNER',$gen_before,'d8000000-0000-0000-0000-0000000000c3','c3');
SQL
)"
case "$stale" in
  *generation*|*ownership*|*stale*|*owner*) echo "PASS CID-RACE-B3 a contact change citing the pre-switch generation ($gen_before) is refused" ;;
  *) echo "FAIL CID-RACE-B3 a contact change citing the stale generation $gen_before was accepted: $stale"; fail=1 ;;
esac

if [ "$fail" = "0" ]; then
  echo "PASS CID-RACE-B1 the ownership switch blocked on the contact change's ownership-row lock"
  echo "PASS CID-RACE-B2 both committed in order: the contact change landed, then ownership moved to the destination"
  exit 0
fi
exit 1
