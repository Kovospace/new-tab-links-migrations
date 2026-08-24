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
   a checksum of each one and refuses to run when a previously applied file has changed.
2. Run the **Build & push migrations image** workflow with the next `version`.
3. Tag this repository with that same version, so the code and the image agree.
4. Bump `flyway.migrations.schema.version` in the backend, in the same commit that starts
   depending on the new migration.

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
