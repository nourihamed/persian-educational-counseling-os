-- =============================================================================
-- PHASE 2 — TEST-ENVIRONMENT ROLES (NOT PRODUCTION PROVISIONING)
-- Non-superuser, NOLOGIN roles used with SET SESSION AUTHORIZATION to test
-- privilege boundaries in a throwaway local database. Production role design,
-- credentials, and owner separation are deployment work and are NOT claimed here.
-- Synthetic data only (D-014). Idempotent. Roles are CLUSTER-wide: superseded
-- roles (e.g. v2 app_rt) are intentionally NOT dropped here; drop them manually
-- on a dedicated test cluster if needed.
--
-- Role intent (test model):
--   app_t1, app_t2   ordinary runtime roles, one per tenant; may only consume credit
--   issuer_rt        purchase-issuance path (stands in for a verified-payment handler)
--   adjuster_rt      refund / cancellation_release / adjustment path
--   nogrant_rt       holds no EXECUTE grant; proves default-deny
-- The owner ('postgres' in the test environment) is TRUSTED by design.
-- =============================================================================
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['app_t1', 'app_t2', 'issuer_rt', 'adjuster_rt', 'nogrant_rt'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format('CREATE ROLE %I NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE', r);
    END IF;
  END LOOP;
END
$$;
