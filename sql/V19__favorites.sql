-- =============================================================================
-- V19 - favourite links, and a profile setting that switches them on
--
-- The extension can now mark a link as a favourite and gather its profile's
-- favourites in one place on the dashboard. Two columns, for the two halves:
--
--   link.favorite             - whether this link is one of the favourites.
--                               It describes the link, not the device that
--                               starred it, exactly like
--                               link_subgroup.catch_links_into_tab_group in
--                               V5, so it has to live on the row: a pull
--                               replaces a profile wholesale from the
--                               snapshot, and a column the snapshot cannot
--                               carry does not survive the next sync.
--   profile.enable_favorites  - whether the profile uses the feature at all.
--                               A profile setting like hide_tips in V8,
--                               riding on the profile row for the reason
--                               given in V6.
--
-- Both NOT NULL DEFAULT false, which backfills every existing row with false:
-- no link is a favourite yet and no profile has the feature on, which is
-- exactly how every account behaves before this migration. Absent on a
-- pushed upsert also reads as false, as it does for every flag but the two
-- recording settings (V17, V18).
--
-- Additive and backfilled by its own default.
-- =============================================================================


ALTER TABLE link
    ADD COLUMN favorite boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN link.favorite IS
    'Whether this link is one of its profile''s favourites.';


ALTER TABLE profile
    ADD COLUMN enable_favorites boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN profile.enable_favorites IS
    'Whether this profile shows favourite links and lets links be marked as favourites.';
