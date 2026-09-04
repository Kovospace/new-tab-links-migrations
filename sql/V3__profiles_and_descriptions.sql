-- =============================================================================
-- V3 - profiles above environments, and the descriptive fields the extension
--      has always had locally
--
-- Two-way synchronization with the browser extension is what forces this. The
-- extension's local model is one level deeper than the server's - it groups
-- environments into profiles - and it carries a free-text description on an
-- environment, a group and a subgroup, plus a "default collapsed" flag that is
-- a property of the subgroup rather than a record of how the user last left it.
-- None of that could travel to the server before, so it could not survive a
-- reinstall.
--
-- This migration runs against databases that already hold real accounts, so
-- every step here is either additive or backfilled before it is constrained.
-- Nothing is dropped and nothing is rewritten in place.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Profiles
-- -----------------------------------------------------------------------------

-- The new top of the hierarchy: app_user -> profile -> environment -> ...
--
-- ON DELETE CASCADE for the same reason as every other level: the application
-- holds no inverse mappings and issues a single DELETE. Note that environment
-- now has two cascade paths to app_user, directly and through profile.
-- PostgreSQL is happy with that; both paths delete the same rows.
--
-- The owning column is user_id, matching environment, user_device and every
-- other table that points at an account, even though the entity calls the
-- field "owner".
CREATE TABLE profile (
    id         uuid         NOT NULL,
    user_id    uuid         NOT NULL,
    name       varchar(120) NOT NULL,
    position   integer      NOT NULL,
    created_at timestamptz  NOT NULL,
    updated_at timestamptz  NOT NULL,
    CONSTRAINT pk_profile      PRIMARY KEY (id),
    CONSTRAINT fk_profile_user FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE
);
CREATE INDEX ix_profile_user_position ON profile (user_id, position);

-- One profile per account that already owns something, to hang the existing
-- environments off. Accounts with no environments get none: they have nothing
-- to place, and the first profile they create will be their own.
--
-- gen_random_uuid() is built into PostgreSQL from 13 onwards, so this needs no
-- extension. The name matches what the extension calls its own first profile.
INSERT INTO profile (id, user_id, name, position, created_at, updated_at)
SELECT gen_random_uuid(), owners.user_id, 'Default', 0, now(), now()
FROM (SELECT DISTINCT user_id FROM environment) AS owners;


-- -----------------------------------------------------------------------------
-- environment gains its profile
--
-- Added nullable, backfilled, and only then constrained - the order that lets
-- a populated database take this migration. Doing it in one step would fail on
-- the first existing row.
--
-- environment.user_id deliberately stays. It is denormalised now, because the
-- owner is reachable through profile, but every ownership-scoped query in the
-- application joins on it and every one of them keeps working untouched.
-- -----------------------------------------------------------------------------

ALTER TABLE environment ADD COLUMN profile_id uuid;

UPDATE environment
SET profile_id = profile.id
FROM profile
WHERE profile.user_id = environment.user_id;

ALTER TABLE environment ALTER COLUMN profile_id SET NOT NULL;

ALTER TABLE environment ADD CONSTRAINT fk_environment_profile
    FOREIGN KEY (profile_id) REFERENCES profile (id) ON DELETE CASCADE;

CREATE INDEX ix_environment_profile_position ON environment (profile_id, position);


-- -----------------------------------------------------------------------------
-- Descriptions
--
-- Nullable and unconstrained: a description is optional everywhere it exists,
-- and an account that has never had one keeps NULL rather than an empty string,
-- so "never written" stays distinguishable from "deliberately cleared".
-- -----------------------------------------------------------------------------

ALTER TABLE environment    ADD COLUMN description varchar(500);
ALTER TABLE link_group     ADD COLUMN description varchar(500);
ALTER TABLE link_subgroup  ADD COLUMN description varchar(500);


-- -----------------------------------------------------------------------------
-- The subgroup's two collapse flags
--
-- link_subgroup.collapsed already exists and records how the user last left the
-- section - live state. default_collapsed is the different question of how the
-- section should start out, which the extension has always distinguished and
-- the server has not. Existing rows take false, which is how every subgroup
-- behaves today.
-- -----------------------------------------------------------------------------

ALTER TABLE link_subgroup
    ADD COLUMN default_collapsed boolean NOT NULL DEFAULT false;
