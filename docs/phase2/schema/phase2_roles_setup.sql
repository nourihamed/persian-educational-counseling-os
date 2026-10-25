-- =============================================================================
-- PHASE 2 — TEST-ENVIRONMENT ROLE SETUP (NOT PRODUCTION PROVISIONING)
-- Creates a non-owner runtime role used only to test privilege boundaries in a
-- throwaway local database. Production role design is OUT OF SCOPE for Phase 2
-- and belongs to deployment/hardening work. Synthetic data only (D-014).
-- Idempotent: safe to run more than once.
-- =============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_rt') THEN
    CREATE ROLE app_rt NOLOGIN;
  END IF;
END
$$;
