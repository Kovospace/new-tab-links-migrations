-- =============================================================================
-- V9 - the recently closed tabs of a profile
--
-- The first entity kind to arrive since V3 gave the hierarchy its profiles.
-- Everything added between the two was a column on a row that already existed;
-- this is a table, because a closed tab is a record of its own and there are
-- many of them per profile.
--
-- It hangs off the profile directly and not off an environment or a group. A
-- closed tab is not filed anywhere - the user closed a tab, and the panel that
-- lists them is per profile, exactly like the profile's other settings. Giving
-- it a place in the link hierarchy would mean inventing one.
--
-- This is a log and not user data, which is what shapes the rest of the design:
--
--   * The extension keeps at most fifty per profile and pushes the ones it
--     drops as deletes, so this table sees far more churn than any other. Rows
--     arrive and leave constantly and none of them is edited.
--   * closed_at is the client's clock, not the server's. The extension knows
--     when the tab was closed; the row may only reach the server minutes later,
--     offline for hours, and the list is ordered by when it happened rather
--     than by when it synchronised. Nothing here defaults it - a row without it
--     is a row the backend refuses before it gets this far.
--   * There is no position column. Order is closed_at descending, and it is not
--     something the user arranges.
--
-- The index carries the only query there is: one profile's tabs, newest first.
-- Written without DESC deliberately - PostgreSQL scans a b-tree backwards just
-- as cheaply, and a plain index matches the shape of every other index here.
-- It also carries the delete: pruning removes rows by profile.
--
-- ON DELETE CASCADE for the same reason as every other level, and with the same
-- caveat: the application deletes children explicitly, because ddl-auto=validate
-- does not check delete rules and a schema Hibernate generates for itself has
-- none. The rule is the safety net, not the mechanism.
--
-- Purely additive. Nothing that exists today is touched, and an account that
-- never opens the panel simply has no rows here.
-- =============================================================================


CREATE TABLE closed_tab (
    id          uuid          NOT NULL,
    profile_id  uuid          NOT NULL,
    url         varchar(2048) NOT NULL,
    title       varchar(200)  NOT NULL,
    favicon_url varchar(2048),
    closed_at   timestamptz   NOT NULL,
    device_name varchar(120),
    created_at  timestamptz   NOT NULL,
    updated_at  timestamptz   NOT NULL,
    CONSTRAINT pk_closed_tab         PRIMARY KEY (id),
    CONSTRAINT fk_closed_tab_profile FOREIGN KEY (profile_id)
        REFERENCES profile (id) ON DELETE CASCADE
);

CREATE INDEX ix_closed_tab_profile_closed_at ON closed_tab (profile_id, closed_at);

COMMENT ON COLUMN closed_tab.closed_at IS
    'When the tab was closed, as reported by the device that closed it - never a server clock.';

COMMENT ON COLUMN closed_tab.title IS
    'What the page called itself; empty rather than NULL for a page that never said.';

COMMENT ON COLUMN closed_tab.device_name IS
    'Name of the device the tab was closed on, NULL when that device has no name.';
