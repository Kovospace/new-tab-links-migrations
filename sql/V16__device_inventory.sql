-- =============================================================================
-- V16 - what each extension installation holds, as it last reported it
--
-- The plan limits are slots: the account's first profiles and workspaces
-- synchronise, and whatever an installation holds beyond them stays on that
-- installation only. The server never sees that local-only data, so the
-- account's devices page could not say where it is - unless each installation
-- tells. It does, after a sync cycle whenever its inventory changed:
--
--   PUT /api/v1/users/me/devices/current/inventory
--
-- per profile its account id (null when local only), name and sync state, and
-- per workspace the same plus its number of groups, subgroups and links. Names
-- and counts only - never a link, an address or a group name.
--
-- Two columns on user_device rather than a table of their own, for the reason
-- V15 gave for dismissed_tips: the report is never queried, never joined, and
-- only ever read and replaced whole together with the device it describes. A
-- child table would buy a join and a delete-then-insert per report and nothing
-- else - and living on the row, the report is deleted with the device and with
-- the account by the cascades that already exist, with nothing to keep in step.
--
--   inventory              the report as the installation sent it (jsonb: a
--                          list of profiles, each with its workspaces); the
--                          backend validates its size and shape before
--                          storing it, and stores it as it was sent
--   inventory_reported_at  when the backend received it
--
-- Both are null until the installation's first report, and for the website's
-- own sign-ins, which never report. They are set and cleared together.
--
-- The partial index serves the question the installation limit asks on every
-- sign-in and every refresh - which installations of this account hold a live
-- session right now. refresh_token keeps every revoked row forever (nothing
-- prunes them yet), so without it that question scans an account's whole token
-- history; live rows are a handful per installation.
--
-- Additive: two nullable columns, a CHECK every existing row satisfies, and an
-- index.
-- =============================================================================


ALTER TABLE user_device
    ADD COLUMN inventory             jsonb,
    ADD COLUMN inventory_reported_at timestamptz,
    ADD CONSTRAINT ck_user_device_inventory_reported_together
        CHECK ((inventory IS NULL) = (inventory_reported_at IS NULL));

COMMENT ON COLUMN user_device.inventory IS
    'Profiles and workspaces the installation last reported holding - names, sync states and counts only; null until it reports.';

COMMENT ON COLUMN user_device.inventory_reported_at IS
    'When the installation''s last inventory report was received; null exactly when inventory is.';


CREATE INDEX ix_refresh_token_live_by_user
    ON refresh_token (user_id)
    WHERE revoked_at IS NULL;
