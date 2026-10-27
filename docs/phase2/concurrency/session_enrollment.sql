-- One concurrent claim of the global D-025 mobile+grade key.
-- Parameters: tenant, counselor, student, enrollment, sleep_before, hold.
\set ON_ERROR_STOP on
SELECT pg_sleep(:sleep_before);
BEGIN;
INSERT INTO counselor_students
  (id, tenant_id, counselor_id, student_id, status, started_at)
VALUES (:'enrollment'::uuid, :'tenant'::uuid, :'counselor'::uuid,
        :'student'::uuid, 'active', now());
SELECT pg_sleep(:hold);
COMMIT;
