# Brief — new-tab-links-migrations: usage statistics tables

> **Status:** the extension side is merged (new-tab-links-extension PR #54). It already calls the
> backend endpoints these tables serve; until they exist, the slot stays empty and new-tab
> counts wait in the browser (the last 7 days are kept). Start this repo's work on
> `feature/usage-stats-and-ad-slot`, created from `main`.

**Kind:** implementation. **Branch:** `feature/usage-stats-and-ad-slot` (same name in all four repos).
**Order:** this lands first; the backend depends on it.

## Why
Tabilinks starts counting two things, for the admin page and for ad-network applications:
- **new tabs opened** in the extension, reported anonymously in daily totals;
- **human visitors** to the website, one per visitor per day.

Both are aggregates only. No user, installation, URL or IP is stored — the visitor dedupe keeps a
salted hash for the current day only and deletes it the next night.

## What to add — `sql/V12__usage_statistics.sql` (next free number; check first)

```sql
-- One row per day and metric. Week and month totals are sums at query time, so nothing
-- has to be rolled up at midnight and nothing is lost if a pod restarts across it.
-- The two metrics are never added together; each admin graph reads only its own.
CREATE TABLE daily_metric (
    day     date        NOT NULL,
    metric  varchar(40) NOT NULL,
    value   bigint      NOT NULL DEFAULT 0,
    PRIMARY KEY (day, metric),
    CONSTRAINT daily_metric_value_non_negative CHECK (value >= 0),
    CONSTRAINT daily_metric_known_metric CHECK (metric IN ('new_tabs', 'website_visitors'))
);

-- Today's website visitors, as salted hashes, so a visitor is counted once per day
-- without a cookie. Rows older than today are deleted nightly by the backend.
CREATE TABLE website_visitor_hash (
    day           date  NOT NULL,
    visitor_hash  bytea NOT NULL,
    PRIMARY KEY (day, visitor_hash)
);
```

Follow the repo's own header-comment style (see V9). Append-only: never edit an applied file.

## Acceptance
- Migration applies cleanly on top of the current head.
- The image is built and its tag is what the backend's `flyway.migrations.schema.version` will pin.
