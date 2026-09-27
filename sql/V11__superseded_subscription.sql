-- =============================================================================
-- V11 - the subscription a lifetime purchase replaced
--
-- superseded_subscription_id + superseded_subscription_cancelled_at are a pending
-- chore, not a purchase. When a lifetime purchase lands on a row that rested on a
-- subscription, the lifetime overwrites provider_subscription_id - but the
-- subscription is still live at the provider and would charge again at renewal. Its
-- id is kept here, and the backend cancels it at the provider AFTER the webhook's
-- transaction commits, retrying on a timer until it succeeds:
--   id NULL,     cancelled_at NULL      nothing to cancel
--   id set,      cancelled_at NULL      pending - the retry job picks it up
--   id set,      cancelled_at set       done; kept as the record of what was cancelled
-- A cancellation time without the subscription it belongs to is meaningless, hence
-- ck_user_entitlement_superseded_pair. The provider is the row's payment_provider:
-- there is one, and a lifetime replacing a subscription went through the same one.
--
-- This was first written into V10 after V10 had been released in 0.0.9, which
-- changed V10's checksum and stopped Flyway on every database that had applied it.
-- V10 is back to its released content and the change lives here instead.
-- =============================================================================

ALTER TABLE user_entitlement
    ADD COLUMN superseded_subscription_id            varchar(100),
    ADD COLUMN superseded_subscription_cancelled_at  timestamptz,
    ADD CONSTRAINT ck_user_entitlement_superseded_pair CHECK (
        superseded_subscription_cancelled_at IS NULL OR superseded_subscription_id IS NOT NULL);

-- What the cancellation retry job scans for. Partial, so it holds only the handful of
-- rows still waiting on the provider rather than every entitlement ever sold.
CREATE INDEX ix_user_entitlement_superseded_pending ON user_entitlement (id)
    WHERE superseded_subscription_id IS NOT NULL
      AND superseded_subscription_cancelled_at IS NULL;

COMMENT ON COLUMN user_entitlement.superseded_subscription_id IS
    'Subscription a lifetime purchase replaced; the backend cancels it at the provider.';

COMMENT ON COLUMN user_entitlement.superseded_subscription_cancelled_at IS
    'When the provider confirmed the superseded subscription cancelled; NULL while pending.';
