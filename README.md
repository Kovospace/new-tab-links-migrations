# new-tab-links-migrations

Flyway migrations for
[`new-tab-links-backend`](https://github.com/Kovospace/new-tab-links-backend), shipped as a
Docker image.

## Why this is a separate repository

The backend does **not** migrate its own schema — `spring.flyway.enabled=false`. The schema is
owned here and applied by this image running as a **Kubernetes init container**, before the
application pod starts.

Two processes migrating one schema is a race, and it splits ownership of the schema between an
application and a deployment. Separating them also means the schema can be rolled forward
independently of an application release, and that the application can be scaled to several
replicas without several of them trying to migrate at once.

## The version contract

**The image tag is the schema version.**

- The backend records the version it was written against in the Maven property
  `flyway.migrations.schema.version`, and publishes it at `/actuator/info` as
  `build.flywayMigrationsSchemaVersion`.
- The deployment pins this image to the same value.
- A running pod can therefore be checked against the migration image that actually ran.

The application runs with `spring.jpa.hibernate.ddl-auto=validate`, so a mismatch between the
entity model and the migrated schema stops the pod at startup rather than corrupting data.

## Layout

```
sql/V1__initial_schema.sql    the migrations, in Flyway's default location
Dockerfile                    flyway/flyway + the sql/ directory
```

## Adding a migration

1. Add `sql/V<n>__<short_description>.sql`. **Never edit an applied migration** — Flyway records
   a checksum of each one and refuses to run when a previously applied file has changed. CI
   enforces this: `sql/` must be append-only against the newest tag.
2. Run the **Build & push migrations image** workflow. It reads the newest `x.y.z` tag,
   increases the patch number by one (`0.0.1` when there are no tags), publishes the image
   under that version, and then tags this repository with it — so the code and the image
   agree, and a tag exists only for a version that was really pushed.
3. Bump `flyway.migrations.schema.version` in the backend, in the same commit that starts
   depending on the new migration.

For a minor or major bump, pass the exact version in the workflow's optional `version` input;
the automatic patch bump is skipped. The run fails before building if that tag already exists.

## Validation

Flyway has no offline check — whether a migration is valid is a question only a real Postgres can
answer. CI stands one up as a throwaway service container and applies the migrations to it along
both paths that matter:

| | what it proves |
|---|---|
| **fresh** | an empty database takes every migration from `V1` — what a new environment does |
| **upgrade** | a database migrated to the last released tag takes the new migrations on top — what production does |

It then `pg_dump`s both and requires them to be identical, so a schema can never depend on which
route a database took to get there. On top of that, `sql/` is checked to be append-only since the
newest tag, because an edited migration is a checksum mismatch and a backend that will not start.

This runs on every pull request touching `sql/` or the `Dockerfile`, and again as a gate in the
release run — nothing is published that has not been applied to a database first. The definition
is shared: `.github/workflows/validate-migrations.yml`.

The Postgres major version is pinned in that workflow's `postgres_image` default and **must track
the real database**; validating against a different major can miss a syntax or behaviour change.

## Environment variables

The image carries no connection details. All three of these are **required** — Flyway exits
non-zero without them, which as an init container means the application pod never starts.

| Variable | Example | |
|---|---|---|
| `FLYWAY_URL` | `jdbc:postgresql://postgres:5432/newtablinks` | JDBC url. Note the `jdbc:` prefix — this is not a libpq connection string. |
| `FLYWAY_USER` | `newtablinks` | Needs DDL rights on the schema: the migrations create and alter tables. |
| `FLYWAY_PASSWORD` | — | Supply from a `Secret`, never from the manifest. |

Worth setting when it runs as an init container, where the database may still be coming up:

| Variable | Example | |
|---|---|---|
| `FLYWAY_CONNECT_RETRIES` | `10` | Retry instead of failing the pod on a database that is not yet accepting connections. Defaults to `0` — one attempt. |
| `FLYWAY_CONNECT_RETRIES_INTERVAL` | `5` | Seconds between those retries. |

Already baked into the image — listed so the behaviour is not a surprise, not so it can be
overridden:

| Variable | Value | |
|---|---|---|
| `FLYWAY_CLEAN_DISABLED` | `true` | `clean` drops every object in the schema. An init container that could do that on a misconfiguration is a loaded gun pointed at production data. |
| `FLYWAY_GROUP` | `true` | Applies the pending migrations in one transaction, so a failure rolls back rather than leaving the schema half-migrated. |

Any other Flyway setting follows the same rule — the option name in `SCREAMING_SNAKE_CASE` with a
`FLYWAY_` prefix, so `connectRetries` becomes `FLYWAY_CONNECT_RETRIES`. `flyway help migrate` in
the image lists them.

## Running it by hand

Against a local database:

```bash
docker build -t new-tab-links-migrations:dev .
docker run --rm --add-host=host.docker.internal:host-gateway \
  -e FLYWAY_URL=jdbc:postgresql://host.docker.internal:5432/newtablinks \
  -e FLYWAY_USER=newtablinks \
  -e FLYWAY_PASSWORD=newtablinks \
  new-tab-links-migrations:dev
```

`flyway clean` is disabled in the image (`FLYWAY_CLEAN_DISABLED=true`). It drops every object in
the schema, and an init container that could do that on a misconfiguration is a loaded gun
pointed at production data.

## Schema notes

Things in `V1` that are decisions rather than transcription:

- **`ON DELETE CASCADE` down the whole hierarchy** — `app_user` → `environment` → `link_group` →
  `link_subgroup` → `link`, and from `app_user` to every credential and device table. The
  application holds no inverse mappings and issues a single `DELETE`; without these rules,
  deleting a group, an environment, or an account fails on a foreign key violation.
- **`link.subgroup_id` is `ON DELETE SET NULL`**, not cascade. Deleting a subgroup must not
  destroy the links inside it — they fall back to sitting directly under their group, which is
  where a link with no subgroup is rendered anyway.
- **`app_user.password_hash` is nullable.** An account created through Google never has a
  password; it signs the browser extension in with a single-use connect code.
- **Timestamps are `timestamptz`.** The application works exclusively in UTC; a column without a
  zone silently reinterprets values when the server's timezone differs from the JVM's.
- **Constraint names are explicit.** Hibernate's generated names look like
  `FKq1qi1gdg6850nkqc81s7o91ch`, which cannot be referenced from a later migration.

Things in `V10` (the pro entitlement) that the backend relies on and cannot check itself -
`ddl-auto=validate` sees none of them:

- **`uk_payment_webhook_event_provider_event` is the webhook replay protection.** The backend
  claims each provider event by inserting it; a redelivery fails on this index and changes
  nothing. Drop it and every retried webhook is applied twice.
- **CHECK constraints name the allowed sources, statuses, outcomes and providers.** A new value in
  the backend's enums needs a migration here first, or the insert fails at runtime.
- **`charged_currency` is checked for shape, not against EUR/USD**, on purpose: a payment in an
  unexpected currency must still be recordable.
