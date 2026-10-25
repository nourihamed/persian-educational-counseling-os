-- One concurrent draft-version creation for the same template and version number.
-- Parameters via psql -v: tenant, template, vid, version, sleep_before, hold.
\set ON_ERROR_STOP on
SELECT pg_sleep(:sleep_before);
BEGIN;
INSERT INTO program_versions (id, tenant_id, program_template_id, version_number, payload_json)
VALUES (:'vid'::uuid, :'tenant'::uuid, :'template'::uuid, :version, '{"synthetic":true}');
SELECT pg_sleep(:hold);
COMMIT;
