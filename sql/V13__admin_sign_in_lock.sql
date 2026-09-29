-- =============================================================================
-- V13 - admin sign-in lockout, shared by every replica
--
-- The operator's sign-in is one fixed username and password, with no account
-- behind it, so the per-account failed_login_attempts on app_user cannot guard
-- it. The backend counted consecutive failures in memory instead - which means
-- per pod: with two replicas an attacker gets twice the guesses before either
-- locks, and a restart forgets them all. The count moves here, where every
-- replica reads and writes the same one.
--
-- One row, not one per presented username: keying by whatever the caller typed
-- would let anyone grow the table without bound, and there is only one admin.
--
--   * ck_admin_sign_in_lock_single_row keeps it one row. The backend writes it
--     with an upsert on the primary key, so no seed row is needed and a row that
--     somehow went missing is recreated by the next failure rather than silently
--     disabling the lockout.
--   * locked_until is compared with the database's now(), never a pod's clock,
--     so replicas cannot disagree about when the lock lifts.
--
-- Purely additive. Nothing that exists today is touched.
-- =============================================================================


CREATE TABLE admin_sign_in_lock (
    id                    smallint    NOT NULL,
    consecutive_failures  integer     NOT NULL DEFAULT 0,
    locked_until          timestamptz,
    CONSTRAINT pk_admin_sign_in_lock                       PRIMARY KEY (id),
    CONSTRAINT ck_admin_sign_in_lock_single_row            CHECK (id = 1),
    CONSTRAINT ck_admin_sign_in_lock_failures_non_negative CHECK (consecutive_failures >= 0)
);

COMMENT ON COLUMN admin_sign_in_lock.consecutive_failures IS
    'Failed operator sign-ins since the last success or the last lock expiry, across all replicas.';

COMMENT ON COLUMN admin_sign_in_lock.locked_until IS
    'When operator sign-in is accepted again; NULL when not locked. Compared with now().';
