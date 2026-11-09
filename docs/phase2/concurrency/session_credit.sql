-- One concurrent credit operation. Parameters via psql -v: tenant, student, key, sleep_before, hold.
\set ON_ERROR_STOP on
SELECT pg_sleep(:sleep_before);
BEGIN;
SELECT post_credit_transaction(:'tenant'::uuid, 'activation_consume', -1, :'student'::uuid, NULL, :'key', NULL, NULL);
SELECT pg_sleep(:hold);
COMMIT;
