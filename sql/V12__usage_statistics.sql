-- =============================================================================
-- V12 - usage statistics: daily totals, and today's website visitors
--
-- Tabilinks starts counting two things, for the admin page and for ad-network
-- applications: new tabs opened in the extension, and human visitors to the
-- website. Both are aggregates and nothing else. No user, installation, URL or
-- IP address is stored anywhere in either table, and neither table references
-- another - there is no account to cascade from, by design.
--
-- daily_metric holds one row per day and metric. Week and month totals are sums
-- at query time, so nothing has to be rolled up at midnight and nothing is lost
-- if a pod restarts across it. The backend adds to a day's row with an upsert,
-- which the primary key is what makes possible. The two metrics are never added
-- together; each admin graph reads only its own.
--
--   * ck_daily_metric_known_metric names the metrics there are. A new one in the
--     backend needs a migration here first, or its insert fails at runtime -
--     ddl-auto=validate does not see CHECK constraints.
--   * day is a date, not a timestamp: the backend decides which day a count
--     belongs to (UTC), and the table only files it.
--
-- website_visitor_hash is how a visitor is counted once per day without a
-- cookie. The backend keeps a salted hash of the visitor for the current day;
-- the primary key turns a second visit into a conflict that counts nothing.
-- Rows older than today are deleted nightly by the backend, so the table only
-- ever holds one day, and a hash cannot be matched across days.
--
-- Purely additive. Nothing that exists today is touched.
-- =============================================================================


CREATE TABLE daily_metric (
    day     date        NOT NULL,
    metric  varchar(40) NOT NULL,
    value   bigint      NOT NULL DEFAULT 0,
    CONSTRAINT pk_daily_metric                    PRIMARY KEY (day, metric),
    CONSTRAINT ck_daily_metric_value_non_negative CHECK (value >= 0),
    CONSTRAINT ck_daily_metric_known_metric       CHECK (metric IN ('new_tabs', 'website_visitors'))
);

CREATE TABLE website_visitor_hash (
    day           date  NOT NULL,
    visitor_hash  bytea NOT NULL,
    CONSTRAINT pk_website_visitor_hash PRIMARY KEY (day, visitor_hash)
);

COMMENT ON COLUMN daily_metric.value IS
    'Total for that day and metric; week and month totals are sums of these rows.';

COMMENT ON COLUMN website_visitor_hash.visitor_hash IS
    'Salted hash of a visitor for this day only - never an IP or anything reversible to one.';
