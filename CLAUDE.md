# CLAUDE.md

Flyway SQL for `new-tab-links-backend`, shipped as an image that runs as an init container. The
backend runs `ddl-auto=validate` against what this produces and never migrates anything itself.
`README.md` has the why, the version contract and the release workflow; this file is the map.

## Rules

- **Never edit an applied migration.** `sql/` is append-only against the newest tag; CI refuses
  anything else. A change is always a new `V<n>__<description>.sql`.
- The backend's `flyway.migrations.schema.version` (in its `pom.xml`) bumps in the same commit
  that starts depending on a new migration.
- `ddl-auto=validate` checks columns and types only — not unique indexes, CHECK constraints or
  `ON DELETE` rules. Anything the application relies on from those is verified only against a
  database this image built.
- Branches: `feature/**` or `bugfix/**` only, named the same as the backend branch the work
  belongs to. Commit only when asked.

## Where each table is defined

Read the one file a question needs, from the line given — not the whole of `V1`.

| Table | Created | Changed later |
|---|---|---|
| `app_user` | `V1:25` | |
| `user_identity` | `V1:45` | |
| `user_device` | `V1:63` | `V4` — `installation_id`; old identity constraint replaced by two partial unique indexes |
| `emailed_token` | `V1:86` | |
| `single_use_code` | `V1:104` | |
| `refresh_token` | `V1:122` | |
| `environment` | `V1:154` | `V3` — `profile_id` (NOT NULL), `description` |
| `link_group` | `V1:167` | `V3` — `description` |
| `link_subgroup` | `V1:180` | `V3` — `description`, `default_collapsed`; `V5` — `catch_links_into_tab_group`; `V7` — `color` |
| `link` | `V1:194` | |
| `visitor_token` | `V2:24` | |
| `profile` | `V3:33` | `V6` — drag and drop; `V8` — hide tips |
| `closed_tab` | `V9:42` | |

`V1:25` means `sql/V1__initial_schema.sql`, line 25.

## What a delete takes with it

Every foreign key cascades **except one**:

- `app_user` → `user_identity`, `user_device`, `emailed_token`, `single_use_code`,
  `refresh_token`, `environment`, `profile`: `ON DELETE CASCADE`
- `user_device` → `refresh_token`: `CASCADE`
- `profile` → `environment` → `link_group` → `link_subgroup`, `link`: `CASCADE`
- `profile` → `closed_tab`: `CASCADE`
- **`link_subgroup` → `link`: `ON DELETE SET NULL`.** Deleting a subgroup keeps its links and
  moves them up to the group.

Regenerate the table index with
`grep -nE '^\s*(CREATE TABLE|ALTER TABLE)' sql/*` and the delete rules with
`grep -n REFERENCES sql/*` when a migration is added.
