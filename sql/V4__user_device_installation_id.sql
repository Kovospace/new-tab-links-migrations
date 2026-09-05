-- =============================================================================
-- V4 - identify a device by the installation that reported it, not by the
--      names it happened to send
--
-- user_device has been keyed on (user_id, device_name, browser_name) since V1,
-- on the reasoning that a machine and a browser on it name a device. Neither
-- half of that pair can carry the weight.
--
-- The extension builds its device name from navigator.platform, which is
-- deprecated, frozen, and names the operating system rather than the browser:
-- every installation on one machine sends the same string. The browser name is
-- parsed from the user agent, and Chromium forks impersonate Chrome there on
-- purpose - Brave ships a Chrome-identical user agent to resist fingerprinting.
-- Two Chromium browsers on one Linux machine therefore produce an identical
-- key, collapse into one row, and share it: the device list undercounts, and
-- signing that device out revokes the tokens of both browsers, because refresh
-- tokens hang off the row they collided on.
--
-- The extension already mints a per-installation UUID and keeps it in
-- chrome.storage.local for as long as it stays installed. It has been sending
-- it as originDeviceId on every pushed change; it now also sends it when it
-- signs in, and that is what identifies the device.
--
-- Runs against databases holding real accounts. The column is added nullable
-- and nothing is backfilled: a device row predating this cannot be attributed
-- to an installation, and guessing would be worse than leaving it. The backend
-- adopts such a row the first time the installation that owns it signs in
-- again, so existing devices are claimed rather than duplicated.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- The installation that reported the device
-- -----------------------------------------------------------------------------

-- Nullable, and stays nullable. Two kinds of row legitimately have no
-- installation: those created before this migration, and those created by the
-- website, which signs in as itself and has no installation identity of its own.
ALTER TABLE user_device
    ADD COLUMN installation_id uuid;

COMMENT ON COLUMN user_device.installation_id IS
    'Identifier the client installation minted for itself; null for rows predating V4 and for the website.';


-- -----------------------------------------------------------------------------
-- The identity constraint moves
-- -----------------------------------------------------------------------------

-- Both replacements are partial, so they divide the table between them rather
-- than competing over it, and neither can be expressed as a table constraint.
--
-- PostgreSQL treats nulls as distinct in a unique index, so a plain
-- UNIQUE (user_id, installation_id) would permit unlimited rows with a null
-- installation and enforce nothing on them. The second index is what keeps the
-- old rule for exactly those rows - website sign-ins and pre-V4 devices - so
-- nothing that worked before this migration loses its guarantee.
ALTER TABLE user_device
    DROP CONSTRAINT uk_user_device_identity;

CREATE UNIQUE INDEX uk_user_device_installation
    ON user_device (user_id, installation_id)
    WHERE installation_id IS NOT NULL;

CREATE UNIQUE INDEX uk_user_device_unattributed
    ON user_device (user_id, device_name, browser_name)
    WHERE installation_id IS NULL;
