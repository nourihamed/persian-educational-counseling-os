-- One concurrent identity-key change on a student (D-025 identity guard race).
-- Parameters: student, new_mobile, sleep_before.
\set ON_ERROR_STOP on
SELECT pg_sleep(:sleep_before);
BEGIN;
UPDATE students SET mobile_normalized = :'new_mobile' WHERE id = :'student'::uuid;
COMMIT;
