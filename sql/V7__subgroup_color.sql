-- =============================================================================
-- V7 - a subgroup carries the colour of its Chrome tab group
--
-- The extension paints the browser tab group of a subgroup, and the colour it
-- uses is a property of the subgroup rather than of the device that picked it:
-- the same section should look the same on every browser the account is signed
-- in on. Without a column for it a pull would wipe the colour everywhere else,
-- because a pull replaces a profile wholesale from the snapshot and a column
-- the snapshot cannot carry does not survive the next sync.
--
-- Stored as plain text, deliberately, and not as an enum or a check constraint.
-- The vocabulary is Chrome's - grey, blue, red, yellow, green, pink, purple,
-- cyan and orange - so it is Chrome that gets to extend it. A tenth colour in
-- some future release should reach the row without waiting for a backend
-- release, and a value this database refuses is a subgroup the extension cannot
-- push at all. Length is capped at 16 because the longest name Chrome has is
-- six characters and nothing here is free text.
--
-- Additive and NULL-able, unlike the boolean settings that came before it: an
-- absent colour is not "no colour", it is a subgroup nobody has assigned one to
-- yet. Existing rows therefore read as NULL and the extension gives them a
-- colour the next time it sees them.
-- =============================================================================


ALTER TABLE link_subgroup
    ADD COLUMN color varchar(16);

COMMENT ON COLUMN link_subgroup.color IS
    'Name of the Chrome tab group colour this subgroup is painted with, NULL when it has none.';
