-- =============================================================================
-- V2 - the visitor token, a metered pass for anonymous callers
--
-- Two endpoints disclose whether a username is registered: the lookup the
-- registration form makes while somebody types, and registration itself, which
-- refuses a taken name with 409. Neither can be closed without losing a
-- feature, so the backend meters them instead: a caller asks for a token, may
-- not spend it immediately, may not spend it faster than a person types, and
-- may spend it only so many times.
--
-- Everything about the pace and the quota is configuration on the backend
-- (newtablinks.visitor-token.*), not a constraint here. This table only has to
-- count, and to be cheap to look up and cheap to delete.
-- =============================================================================

-- One row per page load, deleted wholesale once expired. Nothing references it
-- and nothing may ever depend on one surviving: it carries no identity, belongs
-- to no account, and unlocks no data.
--
-- token_hash is the SHA-256 of the value handed out, Base64 encoded, exactly as
-- every other bearer value in this schema is stored. UNIQUE rather than merely
-- indexed: the lookup expects at most one row, and the index the constraint
-- creates is the one every guarded request uses.
CREATE TABLE visitor_token (
    id           uuid         NOT NULL,
    token_hash   varchar(100) NOT NULL,
    expires_at   timestamptz  NOT NULL,
    usage_count  integer      NOT NULL DEFAULT 0,
    last_used_at timestamptz,
    created_at   timestamptz  NOT NULL,
    updated_at   timestamptz  NOT NULL,
    CONSTRAINT pk_visitor_token            PRIMARY KEY (id),
    CONSTRAINT uk_visitor_token_token_hash UNIQUE (token_hash),
    CONSTRAINT ck_visitor_token_usage_count CHECK (usage_count >= 0)
);

-- The hourly sweep deletes by expiry alone, and this table is the one in the
-- schema that turns over fastest - a full scan per sweep is the one avoidable
-- cost here.
CREATE INDEX ix_visitor_token_expires_at ON visitor_token (expires_at);
