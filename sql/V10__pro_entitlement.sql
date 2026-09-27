-- =============================================================================
-- V10 - the pro entitlement, and the webhook events that write it
--
-- The payment provider is a dumb signal. It says "this account is paid until X",
-- through a signed webhook, and the backend writes that into its own tables. Nothing
-- in the application asks the provider on a request whether somebody is pro: the
-- answer is here, in user_entitlement, and the provider could be swapped without a
-- change to this table beyond a word in one CHECK constraint.
--
-- Two tables:
--
--   * user_entitlement - at most one row per account: what makes it pro, until when,
--     and what was charged for it.
--   * payment_webhook_event - one row per provider event ever received, whose unique
--     index is the whole of the replay protection.
--
-- The backend runs ddl-auto=validate, which checks tables, columns and types and
-- NOTHING else. Every CHECK, the unique index on the event id and the ON DELETE
-- rule below exist only here; a schema Hibernate generates for itself has none of
-- them. The replay guarantee in particular is a unique index that nothing in the
-- backend verifies at startup, which is why its test runs against a database this
-- image built.
--
-- Purely additive. Nothing that exists today is touched, and an account that never
-- pays simply has no row.
-- =============================================================================


-- What makes an account pro, and until when.
--
-- source says where it came from:
--   LIFETIME      a one-time purchase; paid_until is NULL, it never runs out
--   SUBSCRIPTION  a recurring payment; paid_until is the end of the paid period
--   GRANT         given by the operator, no money involved; no provider columns.
--                 In the model now so the whole pro path can be exercised without a
--                 real card - the endpoint that writes it comes later.
--
-- status is the provider's lifecycle, mapped:
--   ACTIVE            paid and in good standing
--   PAST_DUE          a renewal failed and is being retried. MARKS, never revokes:
--                     the user keeps what they already paid for until paid_until
--   SCHEDULED_CANCEL  cancelled at period end; runs out at paid_until, no further
--                     charge will be attempted
--   CANCELED          cancelled outright; nothing more will be charged
--   EXPIRED           the period ended without a new payment
--   REFUNDED          the money went back; grants nothing from that moment
--
-- charged_amount_minor_units + charged_currency are what the customer actually paid,
-- in cents, in the currency Creem charged - the only record of it this side of the
-- provider, and what a refund has to be judged against. Both or neither.
-- The currency is checked for shape, not against a list: a CHECK naming EUR and USD
-- would make an unexpected currency fail the webhook that carries it, and a payment
-- that cannot be recorded is worse than one in an odd currency.
--
-- last_provider_event_at is the provider's own timestamp of the newest event applied
-- to this row. Webhooks arrive out of order - Creem retries over 24 hours, the last
-- gap six hours long - so an event older than this is refused rather than allowed to
-- roll the row back.
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
-- ON DELETE CASCADE like every other table naming an account. The application
-- deletes the row explicitly before the account, because ddl-auto=validate does not
-- check delete rules; the rule is the safety net, not the mechanism.
CREATE TABLE user_entitlement (
    id                          uuid         NOT NULL,
    user_id                     uuid         NOT NULL,
    source                      varchar(20)  NOT NULL,
    status                      varchar(30)  NOT NULL,
    paid_until                  timestamptz,
    charged_amount_minor_units  bigint,
    charged_currency            varchar(3),
    payment_provider            varchar(20),
    provider_customer_id        varchar(100),
    provider_subscription_id    varchar(100),
    provider_product_id         varchar(100),
    provider_order_id           varchar(100),
    last_provider_event_at      timestamptz,
    superseded_subscription_id            varchar(100),
    superseded_subscription_cancelled_at  timestamptz,
    created_at                  timestamptz  NOT NULL,
    updated_at                  timestamptz  NOT NULL,
    CONSTRAINT pk_user_entitlement              PRIMARY KEY (id),
    CONSTRAINT uk_user_entitlement_user         UNIQUE (user_id),
    CONSTRAINT ck_user_entitlement_source       CHECK (source IN ('LIFETIME', 'SUBSCRIPTION', 'GRANT')),
    CONSTRAINT ck_user_entitlement_status       CHECK (status IN (
        'ACTIVE', 'PAST_DUE', 'SCHEDULED_CANCEL', 'CANCELED', 'EXPIRED', 'REFUNDED')),
    CONSTRAINT ck_user_entitlement_provider     CHECK (payment_provider IN ('CREEM')),
    CONSTRAINT ck_user_entitlement_amount       CHECK (charged_amount_minor_units >= 0),
    CONSTRAINT ck_user_entitlement_currency     CHECK (charged_currency ~ '^[A-Z]{3}$'),
    CONSTRAINT ck_user_entitlement_charge_pair  CHECK (
        (charged_amount_minor_units IS NULL) = (charged_currency IS NULL)),
    CONSTRAINT ck_user_entitlement_grant_unpaid CHECK (
        source <> 'GRANT' OR (payment_provider IS NULL AND charged_amount_minor_units IS NULL)),
    CONSTRAINT ck_user_entitlement_superseded_pair CHECK (
        superseded_subscription_cancelled_at IS NULL OR superseded_subscription_id IS NOT NULL),
    CONSTRAINT fk_user_entitlement_user        FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE
);

-- A subscription event that carries no account identifier is attributed through the
-- subscription it belongs to, and failing that through the customer.
CREATE INDEX ix_user_entitlement_provider_subscription ON user_entitlement (provider_subscription_id);
CREATE INDEX ix_user_entitlement_provider_customer     ON user_entitlement (provider_customer_id);

-- What the cancellation retry job scans for. Partial, so it holds only the handful of
-- rows still waiting on the provider rather than every entitlement ever sold.
CREATE INDEX ix_user_entitlement_superseded_pending ON user_entitlement (id)
    WHERE superseded_subscription_id IS NOT NULL
      AND superseded_subscription_cancelled_at IS NULL;

COMMENT ON COLUMN user_entitlement.superseded_subscription_id IS
    'Subscription a lifetime purchase replaced; the backend cancels it at the provider.';

COMMENT ON COLUMN user_entitlement.superseded_subscription_cancelled_at IS
    'When the provider confirmed the superseded subscription cancelled; NULL while pending.';

COMMENT ON COLUMN user_entitlement.paid_until IS
    'End of what has been paid for; NULL for LIFETIME and for a GRANT without an end.';

COMMENT ON COLUMN user_entitlement.last_provider_event_at IS
    'Provider timestamp of the newest event applied; older events are refused.';


-- Every webhook event the provider has delivered, claimed before it is applied.
--
-- The unique index on (payment_provider, provider_event_id) IS the replay
-- protection. The backend inserts the row in a transaction of its own before it
-- touches the entitlement, and a second delivery of the same event - a retry, a
-- replay from the dashboard, an attacker resending a captured request - fails on
-- this index and is answered without effect. An exists-check could not do this: two
-- concurrent deliveries would both pass it.
--
-- outcome and processed_at stay NULL while the claim is in flight. A claim left
-- NULL long after it was taken belongs to a process that died half way, and the
-- backend may take it over when the provider redelivers.
--
-- No foreign key to an account: an event may be attributable to nobody, and that is
-- exactly the row an operator will want to find. It carries no personal data.
CREATE TABLE payment_webhook_event (
    id                 uuid         NOT NULL,
    payment_provider   varchar(20)  NOT NULL,
    provider_event_id  varchar(100) NOT NULL,
    event_type         varchar(60)  NOT NULL,
    outcome            varchar(40),
    processed_at       timestamptz,
    created_at         timestamptz  NOT NULL,
    updated_at         timestamptz  NOT NULL,
    CONSTRAINT pk_payment_webhook_event          PRIMARY KEY (id),
    CONSTRAINT ck_payment_webhook_event_provider CHECK (payment_provider IN ('CREEM')),
    CONSTRAINT ck_payment_webhook_event_outcome  CHECK (outcome IN (
        'APPLIED', 'IGNORED_STALE', 'IGNORED_UNRELATED', 'IGNORED_UNHANDLED_TYPE',
        'UNATTRIBUTED')),
    CONSTRAINT ck_payment_webhook_event_finished CHECK ((outcome IS NULL) = (processed_at IS NULL))
);

CREATE UNIQUE INDEX uk_payment_webhook_event_provider_event
    ON payment_webhook_event (payment_provider, provider_event_id);

COMMENT ON COLUMN payment_webhook_event.outcome IS
    'What applying the event did; NULL while the claim is still in flight.';
