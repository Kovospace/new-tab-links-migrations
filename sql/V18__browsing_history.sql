-- =============================================================================
-- V18 - the browsing history of a profile, and the switch that turns it on
--
-- The extension can now record the pages its user visits, per profile, and
-- synchronise that list between the user's browsers. Two changes, one feature,
-- so one migration: neither is any use without the other.
--
-- 1. profile.record_browsing_history
--
--    The setting, on the profile row like every setting since V6 and for the
--    same reasons: it describes the profile and not the browser that flipped
--    it, and the snapshot a pull replaces a profile from is built from this
--    row.
--
--    DEFAULT false, unlike record_closed_tabs in V17. That column defaulted to
--    true because every profile already recorded its closed tabs and the
--    backfill had to leave them as they were. Here nothing has ever been
--    recorded, and recording a browsing history - stored on a server - is new
--    behaviour that a user has to ask for. It is opt-in: false backfills every
--    existing profile, and a new profile starts off too.
--
--    Turning it off deletes nothing here. The extension removes the visits
--    itself and pushes those deletions like any others; the server only stores
--    the setting.
--
-- 2. visit
--
--    One row per page visited, shaped exactly like closed_tab (V9), and for the
--    same reasons - read V9's header for the long form:
--
--      * It hangs off the profile directly. A visit is not filed anywhere; the
--        panel that lists them is per profile.
--      * It is a log, not user data: no position (order is visited_at,
--        descending), never edited, only inserted and deleted. The extension
--        keeps a rolling list and pushes what it drops as deletes, and the
--        backend trims the oldest beyond the plan's limit after every push.
--      * visited_at is the client's clock, never the server's, and nothing
--        defaults it.
--      * The lengths are the closed tab's: they are the same browser fields,
--        validated by the same request limits on the backend.
--
--    No uniqueness on url, deliberately. The extension keeps at most one visit
--    per page per local day per device, so the same address legitimately
--    appears many times - on other days and from other devices.
--
--    The index carries the snapshot query (one account's visits, newest
--    first, reached through its profiles), the trim, and the delete of a
--    profile's visits - the same single index closed_tab has.
--
--    ON DELETE CASCADE from profile, as for closed_tab: a profile's visits go
--    with it. The application deletes them explicitly first, because
--    ddl-auto=validate does not check delete rules; the rule is the safety net.
--
-- Purely additive. Existing rows gain a column backfilled by its own default;
-- an account that never turns the history on simply has no rows in visit.
-- =============================================================================


ALTER TABLE profile
    ADD COLUMN record_browsing_history boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN profile.record_browsing_history IS
    'Whether this profile records the pages its user visits into visit. Opt-in, off by default.';


CREATE TABLE visit (
    id          uuid          NOT NULL,
    profile_id  uuid          NOT NULL,
    url         varchar(2048) NOT NULL,
    title       varchar(200)  NOT NULL,
    favicon_url varchar(2048),
    visited_at  timestamptz   NOT NULL,
    device_name varchar(120),
    created_at  timestamptz   NOT NULL,
    updated_at  timestamptz   NOT NULL,
    CONSTRAINT pk_visit         PRIMARY KEY (id),
    CONSTRAINT fk_visit_profile FOREIGN KEY (profile_id)
        REFERENCES profile (id) ON DELETE CASCADE
);

CREATE INDEX ix_visit_profile_visited_at ON visit (profile_id, visited_at);

COMMENT ON COLUMN visit.visited_at IS
    'When the page was visited, as reported by the device that visited it - never a server clock.';

COMMENT ON COLUMN visit.title IS
    'What the page called itself; empty rather than NULL for a page that never said.';

COMMENT ON COLUMN visit.device_name IS
    'Name of the device the page was visited on, NULL when that device has no name.';
