-- =============================================================================
-- V17 - a profile decides whether it records the tabs its user closes
--
-- The extension keeps a list of recently closed tabs per profile (closed_tab,
-- V9) and synchronises it to the account. Some users would rather it did not:
-- the list is a piece of browsing history, and it is stored on a server. The
-- extension therefore gains a switch that turns the recording off.
--
-- Like the other settings since V6, it describes the profile and not the
-- browser that flipped it - a user who does not want their closed tabs kept
-- does not want them kept by any of their devices. And like them it rides on
-- the profile row, because the snapshot is built from this row and a pull
-- replaces a profile wholesale from the snapshot.
--
-- DEFAULT true, unlike hide_tips in V8 and unlike the false V6 gave
-- enable_drag_and_drop. NOT NULL DEFAULT backfills every existing profile,
-- and every existing profile records its closed tabs today - so true is the
-- only backfill that leaves them behaving exactly as they did before. This is
-- the reasoning that later made the extension read an unset
-- enable_drag_and_drop as on: the default has to be what profiles already do.
-- Named for recording rather than for not recording so that the column says
-- what the switch says; with a default of true there is no backfill reason to
-- invert it, as there was for hide_tips.
--
-- Turning it off deletes nothing here. The extension removes the closed tabs
-- itself and pushes those deletions like any others; the server only stores
-- the setting.
--
-- Additive and backfilled by its own default.
-- =============================================================================


ALTER TABLE profile
    ADD COLUMN record_closed_tabs boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN profile.record_closed_tabs IS
    'Whether this profile records the browser tabs its user closes into closed_tab.';
