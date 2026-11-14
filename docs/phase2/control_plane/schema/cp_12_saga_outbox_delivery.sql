-- CONTROL PLANE — DRAFT: Transfer Saga outbox delivery, PER REQUIRED RECIPIENT.
-- Apply AFTER cp_01..cp_07 and cp_06_role_privileges_draft.sql. Synthetic only (D-014). Not a migration.
--
-- C-01 (CRITICAL, Supervisor finding on head 8abbbe3) — WHY THIS WAS REDESIGNED
--   The previous version kept ONE delivery row per event. An ownership-switch event must reach BOTH the
--   source and the destination Workspace, and `acknowledge_outbox_event()` marked the whole event
--   acknowledged as soon as the first recipient answered. Retries then stopped for the other Workspace,
--   which could lose the event permanently. That was a real defect, not a theoretical one.
--
-- DESIGN NOW
--   outbox_events               WHAT happened. Immutable. One row.
--   outbox_event_recipients     WHO must receive it. Declared by the producer in the same transaction.
--                               Immutable once written; at least one recipient is required at COMMIT.
--   outbox_deliveries           WHERE each (event, recipient) is in its own delivery: state, lease,
--                               attempts, acknowledgement. Primary key (event_id, workspace_id).
--   inbox_events                WHAT a recipient reported back, keyed (event_id, workspace_id) and
--                               constrained to a DECLARED recipient of that event.
--   outbox_event_completion     An event is complete only when EVERY required recipient has acknowledged.
--
--   Why recipients are declared by the producer rather than derived by a trigger: the required audience is
--   domain knowledge. An ownership switch has a source and a destination; a contact change has the current
--   owner. A trigger guessing from the envelope would silently produce an empty or wrong audience. Instead
--   the producer states the audience and a DEFERRED constraint trigger refuses an event with no recipient.
--
-- WHAT THIS IS NOT, AND WHAT IT CANNOT PROVE
--   * There is NO distributed transaction. The Control Plane and a Workspace are separate databases. The
--     guarantee is: the event is durable with its cause, delivery is at-least-once PER RECIPIENT, and each
--     consumer deduplicates by event id. Nothing here makes the two databases atomic.
--   * payload_hash is a TRANSPORT INTEGRITY check over the stored jsonb rendering. It is NOT authentication
--     of the sender, NOT the signed canonicalization contract (receipt-canon-v1), and NOT a cross-language
--     canonical form. A signed wire format is deferred to Platform Security (OQ-SAGA-1, PS-1..PS-4).
--   * No retry count, backoff curve, lease duration or dead-letter threshold is chosen here. Every such
--     value is a caller argument with no default, because OQ-E is open.
--   * Source freeze/drain, snapshot consistency, destination staging, real dispatcher crash and chaos
--     behaviour are NOT exercised by SQL. They remain acceptance specifications in
--     TRANSFER_SAGA_OUTBOX_INBOX_RECOVERY_CONTRACT.md section 10.
BEGIN;

-- ======================================================================================================
-- Declared audience
-- ======================================================================================================
CREATE TABLE outbox_event_recipients (
    event_id       uuid NOT NULL REFERENCES outbox_events (event_id),
    workspace_id   uuid NOT NULL REFERENCES workspaces (workspace_id),
    recipient_role text NOT NULL CHECK (recipient_role IN ('source','destination','owner')),
    declared_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, workspace_id),
    UNIQUE (event_id, recipient_role)        -- one Workspace per role per event
);
CREATE FUNCTION guard_outbox_recipient_mutation() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'the declared audience of an event is immutable' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER outbox_event_recipients_immutable
  BEFORE UPDATE OR DELETE ON outbox_event_recipients
  FOR EACH ROW EXECUTE FUNCTION guard_outbox_recipient_mutation();

-- An event with no declared recipient would be durable and undeliverable. Refuse it at COMMIT.
-- Deferred triggers run with the CALLER's privileges, so each producing command runs this check inside its
-- own security context (SET CONSTRAINTS ... IMMEDIATE/DEFERRED) rather than leaving it to its executor.
CREATE FUNCTION assert_outbox_event_has_recipient() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.outbox_event_recipients r WHERE r.event_id = NEW.event_id) THEN
    RAISE EXCEPTION 'outbox event % declares no recipient; the producer must state its audience', NEW.event_id
      USING ERRCODE='check_violation';
  END IF;
  RETURN NULL;
END; $body$;
CREATE CONSTRAINT TRIGGER outbox_event_requires_recipient
  AFTER INSERT ON outbox_events
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION assert_outbox_event_has_recipient();

-- ======================================================================================================
-- Per-recipient delivery state
-- ======================================================================================================
CREATE TABLE outbox_deliveries (
    event_id        uuid NOT NULL,
    workspace_id    uuid NOT NULL,
    state           text NOT NULL CHECK (state IN ('pending','leased','sent','acknowledged','dead_letter')),
    attempts        integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
    lease_owner     text CHECK (lease_owner IS NULL OR length(btrim(lease_owner)) > 0),
    lease_expires_at timestamptz,
    last_error_code text,
    first_attempted_at timestamptz,
    last_attempted_at  timestamptz,
    sent_at         timestamptz,
    acknowledged_at timestamptz,
    dead_lettered_at timestamptz,
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (event_id, workspace_id),
    FOREIGN KEY (event_id, workspace_id) REFERENCES outbox_event_recipients (event_id, workspace_id),
    CHECK ((lease_owner IS NULL) = (lease_expires_at IS NULL)),
    CHECK (state <> 'leased'       OR lease_owner IS NOT NULL),
    CHECK ((state = 'acknowledged') = (acknowledged_at IS NOT NULL)),
    CHECK ((state = 'dead_letter')  = (dead_lettered_at IS NOT NULL)),
    CHECK (attempts = 0 OR first_attempted_at IS NOT NULL),
    -- An acknowledgement can only follow a successful send.
    CHECK (state <> 'acknowledged' OR sent_at IS NOT NULL)
);
CREATE INDEX outbox_deliveries_claimable ON outbox_deliveries (state, lease_expires_at);

CREATE TABLE outbox_delivery_audit (
    audit_id     bigserial PRIMARY KEY,
    event_id     uuid NOT NULL,
    workspace_id uuid NOT NULL,
    action       text NOT NULL CHECK (action IN ('dead_letter','redrive','manual_intervention')),
    actor_ref    text NOT NULL CHECK (length(btrim(actor_ref)) > 0),
    reason_code  text NOT NULL CHECK (length(btrim(reason_code)) > 0),
    attempts_at_action integer NOT NULL CHECK (attempts_at_action >= 0),
    recorded_at  timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY (event_id, workspace_id) REFERENCES outbox_event_recipients (event_id, workspace_id)
);
CREATE FUNCTION guard_outbox_delivery_audit() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  RAISE EXCEPTION 'outbox delivery audit is append-only' USING ERRCODE='check_violation';
END; $body$;
CREATE TRIGGER outbox_delivery_audit_append_only
  BEFORE UPDATE OR DELETE ON outbox_delivery_audit
  FOR EACH ROW EXECUTE FUNCTION guard_outbox_delivery_audit();

-- Every declared recipient gets its own pending delivery the moment it is declared.
CREATE FUNCTION create_outbox_delivery() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  INSERT INTO public.outbox_deliveries (event_id, workspace_id, state)
  VALUES (NEW.event_id, NEW.workspace_id, 'pending');
  RETURN NEW;
END; $body$;
CREATE TRIGGER outbox_event_recipients_create_delivery
  AFTER INSERT ON outbox_event_recipients
  FOR EACH ROW EXECUTE FUNCTION create_outbox_delivery();

CREATE FUNCTION guard_outbox_delivery_transition() RETURNS trigger LANGUAGE plpgsql AS $body$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'delivery state cannot be deleted while its recipient exists' USING ERRCODE='check_violation';
  END IF;
  IF (NEW.event_id, NEW.workspace_id) IS DISTINCT FROM (OLD.event_id, OLD.workspace_id) THEN
    RAISE EXCEPTION 'a delivery row cannot move to another event or recipient' USING ERRCODE='check_violation';
  END IF;
  IF NEW.attempts < OLD.attempts THEN
    RAISE EXCEPTION 'attempt count cannot decrease' USING ERRCODE='check_violation';
  END IF;
  IF OLD.state = 'acknowledged' AND NEW.state <> 'acknowledged' THEN
    RAISE EXCEPTION 'an acknowledged delivery is terminal' USING ERRCODE='check_violation';
  END IF;
  IF OLD.acknowledged_at IS NOT NULL AND NEW.acknowledged_at IS DISTINCT FROM OLD.acknowledged_at THEN
    RAISE EXCEPTION 'the acknowledgement time is immutable' USING ERRCODE='check_violation';
  END IF;
  IF OLD.sent_at IS NOT NULL AND NEW.sent_at IS NULL THEN
    RAISE EXCEPTION 'the send record cannot be erased' USING ERRCODE='check_violation';
  END IF;
  IF NOT (
       (OLD.state = 'pending'      AND NEW.state IN ('pending','leased','dead_letter'))
    OR (OLD.state = 'leased'       AND NEW.state IN ('leased','sent','pending','dead_letter'))
    OR (OLD.state = 'sent'         AND NEW.state IN ('sent','acknowledged','pending','leased','dead_letter'))
    OR (OLD.state = 'dead_letter'  AND NEW.state IN ('dead_letter','pending'))
    OR (OLD.state = NEW.state)
  ) THEN
    RAISE EXCEPTION 'illegal delivery transition % -> %', OLD.state, NEW.state USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $body$;
CREATE TRIGGER outbox_deliveries_transition
  BEFORE UPDATE OR DELETE ON outbox_deliveries
  FOR EACH ROW EXECUTE FUNCTION guard_outbox_delivery_transition();

-- ======================================================================================================
-- Dispatcher commands. p_lease_seconds has NO default: the lease duration is an operational parameter that
-- OQ-E leaves open, so the caller must state it and the chosen value stays visible at the call site.
-- Claiming never returns an acknowledged recipient, so a retry targets only what is still outstanding.
-- ======================================================================================================
CREATE FUNCTION claim_outbox_events(p_owner text, p_limit integer, p_lease_seconds integer)
RETURNS TABLE (event_id uuid, workspace_id uuid, recipient_role text, event_type text,
               schema_version integer, payload jsonb, payload_hash bytea, student_id uuid,
               source_workspace_id uuid, destination_workspace_id uuid,
               ownership_generation bigint, correlation_id uuid, attempts integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,pg_temp
AS $$
DECLARE v_now timestamptz;
BEGIN
  IF p_owner IS NULL OR length(btrim(p_owner))=0 OR p_limit IS NULL OR p_limit<1
     OR p_lease_seconds IS NULL OR p_lease_seconds<1 THEN
    RAISE EXCEPTION 'claim arguments are invalid (owner, limit>=1, lease_seconds>=1 are required)'
      USING ERRCODE='invalid_parameter_value';
  END IF;
  v_now := clock_timestamp();
  RETURN QUERY
  WITH claimable AS (
    SELECT d.event_id, d.workspace_id
      FROM public.outbox_deliveries d
     WHERE d.state = 'pending'
        OR (d.state IN ('leased','sent') AND d.lease_expires_at IS NOT NULL AND d.lease_expires_at <= v_now)
     ORDER BY d.updated_at
     LIMIT p_limit
     FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.outbox_deliveries d
       SET state='leased', lease_owner=p_owner,
           lease_expires_at = v_now + make_interval(secs => p_lease_seconds),
           updated_at = v_now
      FROM claimable c
     WHERE d.event_id = c.event_id AND d.workspace_id = c.workspace_id
     RETURNING d.event_id, d.workspace_id, d.attempts
  )
  SELECT e.event_id, c.workspace_id, r.recipient_role, e.event_type, e.schema_version, e.payload,
         e.payload_hash, e.student_id, e.source_workspace_id, e.destination_workspace_id,
         e.ownership_generation, e.correlation_id, c.attempts
    FROM claimed c
    JOIN public.outbox_events e ON e.event_id = c.event_id
    JOIN public.outbox_event_recipients r ON r.event_id = c.event_id AND r.workspace_id = c.workspace_id;
END;
$$;

-- Only the current lease holder for THAT recipient may report, so a dispatcher whose lease expired and was
-- re-claimed elsewhere cannot overwrite the new holder's state.
CREATE FUNCTION record_outbox_sent(p_event_id uuid, p_workspace_id uuid, p_owner text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE d public.outbox_deliveries%ROWTYPE; v_now timestamptz;
BEGIN
  SELECT * INTO d FROM public.outbox_deliveries
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workspace % is not a declared recipient of event %', p_workspace_id, p_event_id
      USING ERRCODE='insufficient_privilege';
  END IF;
  IF d.state='acknowledged' THEN RETURN 'already_acknowledged'; END IF;
  IF d.lease_owner IS DISTINCT FROM p_owner THEN
    RAISE EXCEPTION 'delivery of event % to % is leased by %, not by %',
      p_event_id, p_workspace_id, COALESCE(d.lease_owner,'nobody'), p_owner
      USING ERRCODE='insufficient_privilege';
  END IF;
  v_now := clock_timestamp();
  UPDATE public.outbox_deliveries
     SET state='sent', attempts=attempts+1, last_attempted_at=v_now, sent_at=COALESCE(sent_at,v_now),
         first_attempted_at=COALESCE(first_attempted_at,v_now), last_error_code=NULL, updated_at=v_now
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id;
  RETURN 'sent';
END; $$;

-- H-03: the acknowledgement is bound to the exact event AND the exact recipient Workspace. A Workspace that
-- is not a declared recipient is refused; an acknowledgement before a successful send is refused; an exact
-- replay by the same recipient is idempotent; a conflicting outcome is refused. One recipient's
-- acknowledgement never changes another recipient's delivery.
CREATE FUNCTION acknowledge_outbox_event(p_event_id uuid, p_workspace_id uuid, p_outcome text,
                                         p_outcome_reason text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE d public.outbox_deliveries%ROWTYPE; e public.outbox_events%ROWTYPE; v_now timestamptz; v_existing text;
BEGIN
  IF p_event_id IS NULL OR p_workspace_id IS NULL OR p_outcome IS NULL THEN
    RAISE EXCEPTION 'acknowledgement arguments are invalid' USING ERRCODE='invalid_parameter_value';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.outbox_event_recipients r
                  WHERE r.event_id=p_event_id AND r.workspace_id=p_workspace_id) THEN
    RAISE EXCEPTION 'workspace % is not a declared recipient of event %', p_workspace_id, p_event_id
      USING ERRCODE='insufficient_privilege';
  END IF;

  SELECT * INTO d FROM public.outbox_deliveries
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id FOR UPDATE;

  SELECT outcome INTO v_existing FROM public.inbox_events
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id;
  IF FOUND THEN
    IF v_existing IS DISTINCT FROM p_outcome THEN
      RAISE EXCEPTION 'event % was already acknowledged by workspace % with outcome %',
        p_event_id, p_workspace_id, v_existing USING ERRCODE='unique_violation';
    END IF;
    RETURN 'replayed';
  END IF;

  IF d.sent_at IS NULL THEN
    RAISE EXCEPTION 'event % was never sent to workspace %; an acknowledgement before a successful send is refused',
      p_event_id, p_workspace_id USING ERRCODE='check_violation';
  END IF;
  IF d.state NOT IN ('sent','leased') THEN
    RAISE EXCEPTION 'delivery of event % to % is in state % and cannot be acknowledged',
      p_event_id, p_workspace_id, d.state USING ERRCODE='check_violation';
  END IF;

  SELECT * INTO e FROM public.outbox_events WHERE event_id=p_event_id;
  v_now := clock_timestamp();
  INSERT INTO public.inbox_events (event_id, workspace_id, student_id, ownership_generation,
                                   outcome, outcome_reason, processed_at)
  VALUES (p_event_id, p_workspace_id, e.student_id, e.ownership_generation, p_outcome, p_outcome_reason, v_now);
  UPDATE public.outbox_deliveries
     SET state='acknowledged', acknowledged_at=v_now, lease_owner=NULL, lease_expires_at=NULL, updated_at=v_now
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id;
  RETURN 'acknowledged';
END; $$;

CREATE FUNCTION release_outbox_lease(p_event_id uuid, p_workspace_id uuid, p_owner text, p_error_code text)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE d public.outbox_deliveries%ROWTYPE; v_now timestamptz;
BEGIN
  SELECT * INTO d FROM public.outbox_deliveries
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workspace % is not a declared recipient of event %', p_workspace_id, p_event_id
      USING ERRCODE='insufficient_privilege';
  END IF;
  IF d.state='acknowledged' THEN RETURN 'already_acknowledged'; END IF;
  IF d.lease_owner IS DISTINCT FROM p_owner THEN
    RAISE EXCEPTION 'delivery of event % to % is not leased by %', p_event_id, p_workspace_id, p_owner
      USING ERRCODE='insufficient_privilege';
  END IF;
  v_now := clock_timestamp();
  UPDATE public.outbox_deliveries
     SET state='pending', attempts=attempts+1, last_attempted_at=v_now,
         first_attempted_at=COALESCE(first_attempted_at,v_now),
         last_error_code=p_error_code, lease_owner=NULL, lease_expires_at=NULL, updated_at=v_now
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id;
  RETURN 'released';
END; $$;

CREATE FUNCTION dead_letter_outbox_event(p_event_id uuid, p_workspace_id uuid, p_actor_ref text,
                                         p_reason_code text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE d public.outbox_deliveries%ROWTYPE; v_now timestamptz;
BEGIN
  IF p_actor_ref IS NULL OR length(btrim(p_actor_ref))=0 OR p_reason_code IS NULL OR length(btrim(p_reason_code))=0 THEN
    RAISE EXCEPTION 'dead-letter requires an actor and a reason code' USING ERRCODE='invalid_parameter_value';
  END IF;
  SELECT * INTO d FROM public.outbox_deliveries
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workspace % is not a declared recipient of event %', p_workspace_id, p_event_id
      USING ERRCODE='insufficient_privilege';
  END IF;
  IF d.state='acknowledged' THEN
    RAISE EXCEPTION 'an acknowledged delivery cannot be dead-lettered' USING ERRCODE='check_violation';
  END IF;
  IF d.state='dead_letter' THEN RETURN 'replayed'; END IF;
  v_now := clock_timestamp();
  UPDATE public.outbox_deliveries
     SET state='dead_letter', dead_lettered_at=v_now, lease_owner=NULL, lease_expires_at=NULL,
         last_error_code=p_reason_code, updated_at=v_now
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id;
  INSERT INTO public.outbox_delivery_audit (event_id, workspace_id, action, actor_ref, reason_code, attempts_at_action)
  VALUES (p_event_id, p_workspace_id, 'dead_letter', p_actor_ref, p_reason_code, d.attempts);
  RETURN 'dead_lettered';
END; $$;

-- Re-drive returns one dead-lettered recipient delivery to the queue. The event is never rewritten and no
-- new event is minted: the SAME event id is retried, so the consumer still deduplicates it.
CREATE FUNCTION redrive_outbox_event(p_event_id uuid, p_workspace_id uuid, p_actor_ref text,
                                     p_reason_code text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,pg_temp AS $$
DECLARE d public.outbox_deliveries%ROWTYPE; v_now timestamptz;
BEGIN
  IF p_actor_ref IS NULL OR length(btrim(p_actor_ref))=0 OR p_reason_code IS NULL OR length(btrim(p_reason_code))=0 THEN
    RAISE EXCEPTION 're-drive requires an actor and a reason code' USING ERRCODE='invalid_parameter_value';
  END IF;
  SELECT * INTO d FROM public.outbox_deliveries
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'workspace % is not a declared recipient of event %', p_workspace_id, p_event_id
      USING ERRCODE='insufficient_privilege';
  END IF;
  IF d.state <> 'dead_letter' THEN
    RAISE EXCEPTION 'only a dead-lettered delivery can be re-driven (state %)', d.state USING ERRCODE='check_violation';
  END IF;
  v_now := clock_timestamp();
  UPDATE public.outbox_deliveries
     SET state='pending', dead_lettered_at=NULL, updated_at=v_now
   WHERE event_id=p_event_id AND workspace_id=p_workspace_id;
  INSERT INTO public.outbox_delivery_audit (event_id, workspace_id, action, actor_ref, reason_code, attempts_at_action)
  VALUES (p_event_id, p_workspace_id, 'redrive', p_actor_ref, p_reason_code, d.attempts);
  RETURN 'redriven';
END; $$;

-- An event is complete only when EVERY required recipient has acknowledged it.
CREATE VIEW outbox_event_completion AS
  SELECT e.event_id, e.event_type, e.student_id, e.ownership_generation, e.correlation_id, e.created_at,
         count(r.workspace_id)::integer AS required_recipients,
         count(d.workspace_id) FILTER (WHERE d.state='acknowledged')::integer AS acknowledged_recipients,
         count(r.workspace_id) = count(d.workspace_id) FILTER (WHERE d.state='acknowledged') AS complete
    FROM outbox_events e
    JOIN outbox_event_recipients r ON r.event_id = e.event_id
    LEFT JOIN outbox_deliveries d ON d.event_id = r.event_id AND d.workspace_id = r.workspace_id
   GROUP BY e.event_id, e.event_type, e.student_id, e.ownership_generation, e.correlation_id, e.created_at;

-- Outstanding work, per recipient.
CREATE VIEW outbox_delivery_backlog AS
  SELECT e.event_id, d.workspace_id, r.recipient_role, e.event_type, e.student_id, e.ownership_generation,
         e.correlation_id, e.created_at, d.state, d.attempts, d.lease_owner, d.lease_expires_at,
         d.last_error_code
    FROM outbox_events e
    JOIN outbox_event_recipients r ON r.event_id = e.event_id
    JOIN outbox_deliveries d ON d.event_id = r.event_id AND d.workspace_id = r.workspace_id
   WHERE d.state <> 'acknowledged';

-- ======================================================================================================
-- Identities. The dispatcher may move delivery state and nothing else: it cannot write or alter an event,
-- declare an audience, change ownership, record approvals, or dead-letter/re-drive (operator actions).
-- ======================================================================================================
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_saga_dispatch_function_owner') THEN
    CREATE ROLE cp_saga_dispatch_function_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='cp_saga_dispatcher') THEN
    CREATE ROLE cp_saga_dispatcher NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
END
$roles$;

ALTER TABLE outbox_event_recipients OWNER TO cp_table_owner;
ALTER TABLE outbox_deliveries OWNER TO cp_table_owner;
ALTER TABLE outbox_delivery_audit OWNER TO cp_table_owner;
GRANT SELECT, INSERT, UPDATE ON outbox_deliveries TO cp_saga_dispatch_function_owner;
GRANT SELECT, INSERT ON outbox_delivery_audit TO cp_saga_dispatch_function_owner;
GRANT USAGE, SELECT ON SEQUENCE outbox_delivery_audit_audit_id_seq TO cp_saga_dispatch_function_owner;
GRANT SELECT ON outbox_events, outbox_event_recipients, inbox_events TO cp_saga_dispatch_function_owner;
GRANT INSERT ON inbox_events TO cp_saga_dispatch_function_owner;
-- The event producer declares the audience and the delivery rows its own insert triggers, nothing more.
GRANT INSERT, SELECT ON outbox_event_recipients TO cp_transfer_function_owner;
GRANT INSERT ON outbox_deliveries TO cp_transfer_function_owner;

ALTER FUNCTION claim_outbox_events(text,integer,integer) OWNER TO cp_saga_dispatch_function_owner;
ALTER FUNCTION record_outbox_sent(uuid,uuid,text) OWNER TO cp_saga_dispatch_function_owner;
ALTER FUNCTION acknowledge_outbox_event(uuid,uuid,text,text) OWNER TO cp_saga_dispatch_function_owner;
ALTER FUNCTION release_outbox_lease(uuid,uuid,text,text) OWNER TO cp_saga_dispatch_function_owner;
ALTER FUNCTION dead_letter_outbox_event(uuid,uuid,text,text) OWNER TO cp_saga_dispatch_function_owner;
ALTER FUNCTION redrive_outbox_event(uuid,uuid,text,text) OWNER TO cp_saga_dispatch_function_owner;

REVOKE ALL ON FUNCTION claim_outbox_events(text,integer,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION record_outbox_sent(uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION acknowledge_outbox_event(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION release_outbox_lease(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION dead_letter_outbox_event(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION redrive_outbox_event(uuid,uuid,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION claim_outbox_events(text,integer,integer) TO cp_saga_dispatcher;
GRANT EXECUTE ON FUNCTION record_outbox_sent(uuid,uuid,text) TO cp_saga_dispatcher;
GRANT EXECUTE ON FUNCTION acknowledge_outbox_event(uuid,uuid,text,text) TO cp_saga_dispatcher;
GRANT EXECUTE ON FUNCTION release_outbox_lease(uuid,uuid,text,text) TO cp_saga_dispatcher;
REVOKE ALL ON FUNCTION dead_letter_outbox_event(uuid,uuid,text,text) FROM cp_saga_dispatcher;
REVOKE ALL ON FUNCTION redrive_outbox_event(uuid,uuid,text,text) FROM cp_saga_dispatcher;
GRANT SELECT ON outbox_delivery_backlog, outbox_event_completion TO cp_saga_dispatcher, cp_runtime;
REVOKE ALL ON outbox_deliveries, outbox_delivery_audit, outbox_events, outbox_event_recipients,
              inbox_events, student_ownership, transfer_cases FROM cp_saga_dispatcher;
GRANT SELECT ON outbox_events, outbox_event_recipients TO cp_saga_dispatcher;

COMMIT;
