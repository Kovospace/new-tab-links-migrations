### ---------------------------------------------------------------------------
### Flyway migrations for new-tab-links-backend
###
### Runs as a Kubernetes init container, before the application pod starts. The
### application itself has spring.flyway.enabled=false and never migrates its own
### schema: two things migrating one schema is a race, and it splits ownership of
### the schema between a repository and a deployment.
###
### The image tag IS the schema version. The backend records the version it was
### written against in the Maven property flyway.migrations.schema.version and
### publishes it at /actuator/info as build.flywayMigrationsSchemaVersion, so a
### running pod can be checked against the migration image that actually ran.
###
### Run it with the connection supplied as environment variables:
###
###   docker run --rm \
###     -e FLYWAY_URL=jdbc:postgresql://host:5432/newtablinks \
###     -e FLYWAY_USER=... -e FLYWAY_PASSWORD=... \
###     <registry>/apps/new-tab-links-migrations:<version>
### ---------------------------------------------------------------------------

# Pinned to a specific Flyway minor rather than `latest`: a rebuild of an old
# commit must apply the same migrations with the same engine it was verified on.
FROM flyway/flyway:11.14-alpine

### The migrations themselves. Flyway's default location inside the image.
#
COPY sql/ /flyway/sql/


### `migrate` is the whole job. No `clean` is reachable from here, and
### FLYWAY_CLEAN_DISABLED makes that explicit: `clean` drops every object in the
### schema, and an init container that could do that on a misconfiguration is a
### loaded gun pointed at production data.
#
ENV FLYWAY_CLEAN_DISABLED=true

### Fail loudly rather than half-applying. Postgres runs DDL transactionally, so
### a failed migration rolls back and the init container exits non-zero, which
### stops the application pod from starting against a half-migrated schema.
#
ENV FLYWAY_GROUP=true

ENTRYPOINT ["flyway"]
CMD ["migrate"]
