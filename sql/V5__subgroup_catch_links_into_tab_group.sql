-- =============================================================================
-- V5 - a subgroup can catch navigations into its own Chrome tab group
--
-- The extension gained a per-subgroup switch: with it on, a tab that navigates
-- to any of that subgroup's links is pulled into the subgroup's Chrome tab
-- group, wherever in the browser it was opened from.
--
-- It is a property of the subgroup and not of the device that set it, exactly
-- like default_collapsed, so it has to live on the row rather than in local
-- storage. Without it here a pull would wipe the setting on every device that
-- did not make the change: a pull replaces a profile wholesale from the
-- snapshot, and a column the snapshot cannot carry is a column that does not
-- survive the next sync.
--
-- Additive and backfilled by its own default. Existing rows take false, which
-- is how every subgroup behaves today.
-- =============================================================================


ALTER TABLE link_subgroup
    ADD COLUMN catch_links_into_tab_group boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN link_subgroup.catch_links_into_tab_group IS
    'Whether tabs navigating to this subgroup''s links are pulled into its Chrome tab group.';
