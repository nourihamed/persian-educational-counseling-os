-- =============================================================================
-- CONTROL PLANE — DRAFT: transfer state transition table (PR #11 §5; OQ-E).
-- Enforced by the database: an illegal state change on transfer_cases is rejected.
-- Apply AFTER cp_01 and cp_02. Synthetic data only (D-014). Not a production migration.
-- =============================================================================
BEGIN;

CREATE TABLE transfer_state_transitions (
    from_state text NOT NULL,
    to_state   text NOT NULL,
    PRIMARY KEY (from_state, to_state)
);
INSERT INTO transfer_state_transitions (from_state, to_state) VALUES
 ('requested','approvals_pending'),
 ('approvals_pending','approved'),
 ('approved','preflight_ok'),
 ('preflight_ok','staging'),
 ('staging','staged_verified'),
 ('staged_verified','cutover_frozen'),
 ('cutover_frozen','ownership_switched'),
 ('ownership_switched','projections_finalizing'),
 ('projections_finalizing','completed'),
 -- Non-terminal states may be cancelled or moved to recovery before the ownership switch.
 ('requested','cancelled'),('approvals_pending','cancelled'),('approved','cancelled'),
 ('preflight_ok','cancelled'),('staging','cancelled'),('staged_verified','cancelled'),
 ('staging','failed_recoverable'),('staged_verified','failed_recoverable'),('cutover_frozen','failed_recoverable'),
 ('failed_recoverable','staging'),('failed_recoverable','cutover_frozen'),
 ('failed_recoverable','manual_intervention'),('failed_recoverable','cancelled'),
 -- After the switch, recovery moves forward (no automatic return to the source; PR #11 §5).
 ('ownership_switched','manual_intervention'),('projections_finalizing','manual_intervention'),
 ('manual_intervention','projections_finalizing');
-- Recovery transitions are operationally guarded: before switch, a verified checkpoint may resume;
-- after switch, only forward projection finalization is permitted. Thresholds remain operationally open.

CREATE FUNCTION enforce_transfer_transition() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.state IS NOT DISTINCT FROM OLD.state THEN
        RETURN NEW;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.transfer_state_transitions t
                    WHERE t.from_state = OLD.state AND t.to_state = NEW.state) THEN
        RAISE EXCEPTION 'illegal transfer transition % -> %', OLD.state, NEW.state
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER transfer_cases_transition_guard
    BEFORE UPDATE OF state ON transfer_cases
    FOR EACH ROW EXECUTE FUNCTION enforce_transfer_transition();

-- A transfer must START in 'requested' (closes the INSERT bypass of the UPDATE-only trigger).
CREATE FUNCTION enforce_transfer_initial_state() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.state <> 'requested' THEN
        RAISE EXCEPTION 'transfer must start in requested, got %', NEW.state USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER transfer_cases_initial_state
    BEFORE INSERT ON transfer_cases
    FOR EACH ROW EXECUTE FUNCTION enforce_transfer_initial_state();

COMMIT;
