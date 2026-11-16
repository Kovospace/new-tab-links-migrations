-- =============================================================================
-- V20 - Fair Use limits the operator can change, and per-account raises of them
--
-- The Fair Use Policy limits - every limit a premium account has, and the free
-- plan's too wherever it names none of its own - were configuration only
-- (newtablinks.plan-limits.premium.*), so changing one meant a redeploy, and
-- one account that genuinely needed more could not be given more without
-- giving it to everybody. Two tables:
--
--   fair_use_limits         - the global Fair Use limits, one row. Seeded here
--                             with exactly the values the configuration holds
--                             today, so nothing changes for anybody when this
--                             runs. The backend falls back to the configuration
--                             only if the row is missing. The free plan's own
--                             numbers (free.*) stay in configuration and have
--                             no column here.
--   user_fair_use_override  - one row per account the operator raised. Every
--                             limit is nullable: NULL means "the global value",
--                             a number means "at least this much". The backend
--                             only accepts a number at or above the global
--                             value at the time it is saved; if the global
--                             value later rises past it, the higher of the two
--                             holds, so the row never lowers anything. A row
--                             with every limit NULL is never kept - the
--                             backend deletes it instead. No expiry.
--
-- Every limit is CHECKed >= 1: a limit below one would refuse the very first
-- record of its kind, which is never what anybody meant.
--
-- ck_fair_use_limits_single_row keeps the global table one row, the same way
-- V13 does for admin_sign_in_lock.
--
-- user_fair_use_override is keyed by the account and cascades with it, like
-- every other table naming an account.
--
-- Purely additive. Nothing that exists today is touched.
-- =============================================================================


CREATE TABLE fair_use_limits (
    id                      smallint     NOT NULL,
    profiles                integer      NOT NULL,
    workspaces_per_profile  integer      NOT NULL,
    groups_per_workspace    integer      NOT NULL,
    subgroups_per_group     integer      NOT NULL,
    links_per_workspace     integer      NOT NULL,
    closed_tabs             integer      NOT NULL,
    browsing_history        integer      NOT NULL,
    devices                 integer      NOT NULL,
    updated_at              timestamptz  NOT NULL,
    CONSTRAINT pk_fair_use_limits                    PRIMARY KEY (id),
    CONSTRAINT ck_fair_use_limits_single_row         CHECK (id = 1),
    CONSTRAINT ck_fair_use_limits_profiles           CHECK (profiles >= 1),
    CONSTRAINT ck_fair_use_limits_workspaces         CHECK (workspaces_per_profile >= 1),
    CONSTRAINT ck_fair_use_limits_groups             CHECK (groups_per_workspace >= 1),
    CONSTRAINT ck_fair_use_limits_subgroups          CHECK (subgroups_per_group >= 1),
    CONSTRAINT ck_fair_use_limits_links              CHECK (links_per_workspace >= 1),
    CONSTRAINT ck_fair_use_limits_closed_tabs        CHECK (closed_tabs >= 1),
    CONSTRAINT ck_fair_use_limits_browsing_history   CHECK (browsing_history >= 1),
    CONSTRAINT ck_fair_use_limits_devices            CHECK (devices >= 1)
);

COMMENT ON TABLE fair_use_limits IS
    'The global Fair Use Policy limits - one row. What a premium account gets, and a free one wherever the free plan names no lower number.';

-- Today's newtablinks.plan-limits.premium.* defaults, so the migration changes
-- no account's limits.
INSERT INTO fair_use_limits (
    id, profiles, workspaces_per_profile, groups_per_workspace, subgroups_per_group,
    links_per_workspace, closed_tabs, browsing_history, devices, updated_at)
VALUES (1, 50, 50, 25, 25, 500, 500, 1000, 100, now());


CREATE TABLE user_fair_use_override (
    user_id                 uuid          NOT NULL,
    profiles                integer,
    workspaces_per_profile  integer,
    groups_per_workspace    integer,
    subgroups_per_group     integer,
    links_per_workspace     integer,
    closed_tabs             integer,
    browsing_history        integer,
    devices                 integer,
    note                    varchar(500),
    updated_at              timestamptz   NOT NULL,
    CONSTRAINT pk_user_fair_use_override                  PRIMARY KEY (user_id),
    CONSTRAINT ck_user_fair_use_override_profiles         CHECK (profiles >= 1),
    CONSTRAINT ck_user_fair_use_override_workspaces       CHECK (workspaces_per_profile >= 1),
    CONSTRAINT ck_user_fair_use_override_groups           CHECK (groups_per_workspace >= 1),
    CONSTRAINT ck_user_fair_use_override_subgroups        CHECK (subgroups_per_group >= 1),
    CONSTRAINT ck_user_fair_use_override_links            CHECK (links_per_workspace >= 1),
    CONSTRAINT ck_user_fair_use_override_closed_tabs      CHECK (closed_tabs >= 1),
    CONSTRAINT ck_user_fair_use_override_browsing_history CHECK (browsing_history >= 1),
    CONSTRAINT ck_user_fair_use_override_devices          CHECK (devices >= 1),
    CONSTRAINT fk_user_fair_use_override_user             FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE
);

COMMENT ON TABLE user_fair_use_override IS
    'Fair Use limits raised for one account by the operator. NULL = the global value; a number = at least this much (the higher of it and the global value holds).';

COMMENT ON COLUMN user_fair_use_override.note IS
    'The operator''s free-text reason for the raise.';
