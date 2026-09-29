-- =============================================================================
-- V14 - drop website_visitor_hash
--
-- The backend deduplicated website visitors by a daily HMAC of address and
-- User-Agent, stored here. Behind carrier-grade NAT thousands of people share
-- one address, and browsers now send identical User-Agent strings, so a whole
-- neighbourhood collapsed into a handful of visitors. The website now reports at
-- most once a day itself, and the backend counts every report into daily_metric;
-- nothing reads or writes this table any more.
--
-- Its rows are one day's hashes at most, meaningless after that day, so nothing
-- is lost. The totals already counted stay in daily_metric.
--
-- Release order: only with a backend that no longer maps the table. A pod that
-- still maps it fails ddl-auto=validate at startup, and one already running
-- fails every visit report.
-- =============================================================================


DROP TABLE website_visitor_hash;
