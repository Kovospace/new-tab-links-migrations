-- =============================================================================
-- V6 - a profile carries its own settings, starting with drag and drop
--
-- The extension gained a settings dialog. Its first switch decides whether the
-- links and groups of a profile can be rearranged by dragging them, and it is
-- deliberately a setting of the profile rather than of the browser that flipped
-- it: the user configures a workspace once, not once per device.
--
-- Settings ride on the profile row rather than in a table of their own, for the
-- same reason default_collapsed rides on link_subgroup. A pull replaces a
-- profile wholesale from the snapshot, so anything the snapshot cannot carry is
-- wiped on the next sync - and the snapshot is built from the profile row.
-- A separate table would buy nothing here and cost a join on every pull.
--
-- Additive and backfilled by its own default. Existing profiles take false,
-- which is how every profile behaves today.
-- =============================================================================


ALTER TABLE profile
    ADD COLUMN enable_drag_and_drop boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN profile.enable_drag_and_drop IS
    'Whether this profile lets its links and groups be rearranged by dragging.';
