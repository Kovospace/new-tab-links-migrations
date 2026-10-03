-- =============================================================================
-- V15 - a profile remembers which single tips have been dismissed
--
-- The tips on the new tab page background can be hidden all at once (V8,
-- hide_tips), and now one at a time too: an "I know" on a tip means that tip is
-- never shown again. Like hide_tips it describes the profile and not the
-- browser that clicked it, and for the same reason it needs a column: the next
-- pull replaces a profile wholesale from the snapshot, so a dismissal stored
-- nowhere here would bring the tip back on every other device.
--
-- An array of tip identifiers rather than a table of its own. A tip identifier
-- is a stable name out of the extension's tips.json ("hide-tips",
-- "change-background"), not a row anything refers to: it is never queried,
-- never joined, and only ever read and replaced together with its profile.
-- A child table would buy a join on every pull and nothing else, which is the
-- reasoning that put the other settings on this row (V6).
--
-- NOT NULL DEFAULT '{}' backfills every existing profile with "nothing
-- dismissed", which is the state those profiles are in today. The order is the
-- order the client sent and is kept as sent.
--
-- Additive and backfilled by its own default.
-- =============================================================================


ALTER TABLE profile
    ADD COLUMN dismissed_tips text[] NOT NULL DEFAULT '{}';

COMMENT ON COLUMN profile.dismissed_tips IS
    'Identifiers of the new tab page tips this profile has dismissed one by one.';
