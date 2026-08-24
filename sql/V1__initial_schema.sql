-- =============================================================================
-- V1 - initial schema for new-tab-links-backend
--
-- Owns the schema outright: the application runs with
-- spring.jpa.hibernate.ddl-auto=validate and never alters a table itself.
--
-- Derived from the JPA entity model and then written out by hand, so that
-- constraint names are stable and readable. Hibernate's generated names look
-- like FKq1qi1gdg6850nkqc81s7o91ch, which is unusable in a file people have to
-- maintain and impossible to reference in a later migration.
--
-- Timestamps are `timestamptz`. The application works exclusively in UTC
-- (Instant), and a column without a zone silently reinterprets values when the
-- server's timezone differs from the JVM's.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Accounts
-- -----------------------------------------------------------------------------

-- The owner of everything. password_hash is NULLABLE on purpose: an account
-- created through an external provider never has a password, and is signed in
-- to the browser extension with a single-use connect code instead.
CREATE TABLE app_user (
    id                    uuid         NOT NULL,
    username              varchar(60)  NOT NULL,
    email                 varchar(320) NOT NULL,
    password_hash         varchar(100),
    display_name          varchar(120) NOT NULL,
    status                varchar(30)  NOT NULL,
    failed_login_attempts integer      NOT NULL DEFAULT 0,
    created_at            timestamptz  NOT NULL,
    updated_at            timestamptz  NOT NULL,
    CONSTRAINT pk_app_user               PRIMARY KEY (id),
    CONSTRAINT uk_app_user_username      UNIQUE (username),
    CONSTRAINT uk_app_user_email         UNIQUE (email),
    CONSTRAINT ck_app_user_status        CHECK (status IN ('PENDING_ACTIVATION', 'ACTIVE', 'DISABLED'))
);

-- A link between an account and an external identity provider.
-- The identity is (provider, provider_user_id) and NEVER the email address:
-- addresses change, get reassigned, and some providers do not return one.
-- email_at_provider is diagnostic only and must not be used to match users.
CREATE TABLE user_identity (
    id                uuid         NOT NULL,
    user_id           uuid         NOT NULL,
    provider          varchar(40)  NOT NULL,
    provider_user_id  varchar(255) NOT NULL,
    email_at_provider varchar(320),
    created_at        timestamptz  NOT NULL,
    updated_at        timestamptz  NOT NULL,
    CONSTRAINT pk_user_identity                    PRIMARY KEY (id),
    CONSTRAINT uk_user_identity_provider_subject   UNIQUE (provider, provider_user_id),
    CONSTRAINT ck_user_identity_provider           CHECK (provider IN ('GOOGLE')),
    CONSTRAINT fk_user_identity_user               FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE
);

-- Where an account has been signed in from: one row per machine-and-browser
-- pair. Three browsers on one machine are three devices, because each holds its
-- own tokens and is signed out separately.
CREATE TABLE user_device (
    id           uuid         NOT NULL,
    user_id      uuid         NOT NULL,
    device_name  varchar(120) NOT NULL,
    browser_name varchar(60)  NOT NULL,
    last_used_at timestamptz  NOT NULL,
    created_at   timestamptz  NOT NULL,
    updated_at   timestamptz  NOT NULL,
    CONSTRAINT pk_user_device            PRIMARY KEY (id),
    CONSTRAINT uk_user_device_identity   UNIQUE (user_id, device_name, browser_name),
    CONSTRAINT fk_user_device_user       FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE
);


-- -----------------------------------------------------------------------------
-- Credentials
--
-- Every table below stores a HASH, never the secret itself, so a database leak
-- yields nothing usable. The hash index exists because lookup is always by hash.
-- -----------------------------------------------------------------------------

-- Account activation and password reset links.
CREATE TABLE emailed_token (
    id          uuid        NOT NULL,
    user_id     uuid        NOT NULL,
    token_hash  varchar(100) NOT NULL,
    purpose     varchar(40) NOT NULL,
    expires_at  timestamptz NOT NULL,
    consumed_at timestamptz,
    created_at  timestamptz NOT NULL,
    updated_at  timestamptz NOT NULL,
    CONSTRAINT pk_emailed_token       PRIMARY KEY (id),
    CONSTRAINT ck_emailed_token_purpose CHECK (purpose IN ('ACCOUNT_ACTIVATION', 'PASSWORD_RESET')),
    CONSTRAINT fk_emailed_token_user  FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE
);
CREATE INDEX ix_emailed_token_hash ON emailed_token (token_hash);

-- Short-lived codes exchanged for a token pair: the handoff after a provider
-- sign-in, and the code a user retypes into the browser extension.
CREATE TABLE single_use_code (
    id          uuid         NOT NULL,
    user_id     uuid         NOT NULL,
    code_hash   varchar(100) NOT NULL,
    purpose     varchar(40)  NOT NULL,
    expires_at  timestamptz  NOT NULL,
    consumed_at timestamptz,
    created_at  timestamptz  NOT NULL,
    updated_at  timestamptz  NOT NULL,
    CONSTRAINT pk_single_use_code         PRIMARY KEY (id),
    CONSTRAINT ck_single_use_code_purpose CHECK (purpose IN ('WEB_SESSION_HANDOFF', 'EXTENSION_CONNECT')),
    CONSTRAINT fk_single_use_code_user    FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE
);
CREATE INDEX ix_single_use_code_hash ON single_use_code (code_hash);

-- Long-lived per-device credentials. Rotated on every use, so these rows are
-- numerous and short-lived; user_device is what a person is actually shown.
CREATE TABLE refresh_token (
    id         uuid         NOT NULL,
    user_id    uuid         NOT NULL,
    device_id  uuid         NOT NULL,
    token_hash varchar(100) NOT NULL,
    expires_at timestamptz  NOT NULL,
    revoked_at timestamptz,
    created_at timestamptz  NOT NULL,
    updated_at timestamptz  NOT NULL,
    CONSTRAINT pk_refresh_token        PRIMARY KEY (id),
    CONSTRAINT fk_refresh_token_user   FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE,
    CONSTRAINT fk_refresh_token_device FOREIGN KEY (device_id)
        REFERENCES user_device (id) ON DELETE CASCADE
);
CREATE INDEX ix_refresh_token_hash ON refresh_token (token_hash);


-- -----------------------------------------------------------------------------
-- The link hierarchy
--
-- environment -> link_group -> link_subgroup -> link, every level owned by one
-- account. Deleting a parent deletes its children (ON DELETE CASCADE), which is
-- what makes "delete my account" and "delete this group" work at all: the
-- application holds no inverse mappings and issues a single DELETE.
--
-- The one exception is link.subgroup_id, which is ON DELETE SET NULL: deleting a
-- subgroup must NOT destroy the links inside it. They fall back to sitting
-- directly under the group, which is where they are rendered when they have no
-- subgroup anyway.
-- -----------------------------------------------------------------------------

CREATE TABLE environment (
    id         uuid         NOT NULL,
    user_id    uuid         NOT NULL,
    name       varchar(120) NOT NULL,
    position   integer      NOT NULL,
    created_at timestamptz  NOT NULL,
    updated_at timestamptz  NOT NULL,
    CONSTRAINT pk_environment      PRIMARY KEY (id),
    CONSTRAINT fk_environment_user FOREIGN KEY (user_id)
        REFERENCES app_user (id) ON DELETE CASCADE
);
CREATE INDEX ix_environment_user_position ON environment (user_id, position);

CREATE TABLE link_group (
    id             uuid         NOT NULL,
    environment_id uuid         NOT NULL,
    name           varchar(120) NOT NULL,
    position       integer      NOT NULL,
    created_at     timestamptz  NOT NULL,
    updated_at     timestamptz  NOT NULL,
    CONSTRAINT pk_link_group             PRIMARY KEY (id),
    CONSTRAINT fk_link_group_environment FOREIGN KEY (environment_id)
        REFERENCES environment (id) ON DELETE CASCADE
);
CREATE INDEX ix_link_group_environment_position ON link_group (environment_id, position);

CREATE TABLE link_subgroup (
    id         uuid         NOT NULL,
    group_id   uuid         NOT NULL,
    name       varchar(120) NOT NULL,
    position   integer      NOT NULL,
    collapsed  boolean      NOT NULL DEFAULT false,
    created_at timestamptz  NOT NULL,
    updated_at timestamptz  NOT NULL,
    CONSTRAINT pk_link_subgroup       PRIMARY KEY (id),
    CONSTRAINT fk_link_subgroup_group FOREIGN KEY (group_id)
        REFERENCES link_group (id) ON DELETE CASCADE
);
CREATE INDEX ix_link_subgroup_group_position ON link_subgroup (group_id, position);

CREATE TABLE link (
    id          uuid          NOT NULL,
    group_id    uuid          NOT NULL,
    subgroup_id uuid,
    title       varchar(200)  NOT NULL,
    url         varchar(2048) NOT NULL,
    favicon_url varchar(2048),
    position    integer       NOT NULL,
    created_at  timestamptz   NOT NULL,
    updated_at  timestamptz   NOT NULL,
    CONSTRAINT pk_link          PRIMARY KEY (id),
    CONSTRAINT fk_link_group    FOREIGN KEY (group_id)
        REFERENCES link_group (id) ON DELETE CASCADE,
    CONSTRAINT fk_link_subgroup FOREIGN KEY (subgroup_id)
        REFERENCES link_subgroup (id) ON DELETE SET NULL
);
CREATE INDEX ix_link_group_position    ON link (group_id, position);
CREATE INDEX ix_link_subgroup_position ON link (subgroup_id, position);
