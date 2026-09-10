-- =============================================================================
-- V8 - a profile remembers whether its tips have been dismissed
--
-- The extension writes tips onto the background of the new tab page, and the
-- user can dismiss them. Whether they are dismissed describes the profile and
-- not the browser that clicked the cross, exactly like enable_drag_and_drop in
-- V6: the person makes that decision once, not once per device. Without a
-- column for it the next pull, which replaces a profile wholesale from the
-- snapshot, would put the tips back on every other device.
--
-- The second setting to ride on the profile row rather than in a table of its
-- own, for the reason given in V6 - the snapshot is built from this row, and a
-- separate table would buy nothing but a join on every pull.
--
-- Named "hide" and not "show" because of the default. NOT NULL DEFAULT false
-- backfills every existing profile with false, and false has to mean "the tips
-- are visible" so that a profile predating this column behaves exactly as it
-- did before. A "show_tips" column defaulting to false would silently hide the
-- tips on every account that already exists.
--
-- Additive and backfilled by its own default.
-- =============================================================================


ALTER TABLE profile
    ADD COLUMN hide_tips boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN profile.hide_tips IS
    'Whether this profile has dismissed the tips shown on the new tab page background.';
