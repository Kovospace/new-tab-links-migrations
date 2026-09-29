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

## Changing what the cluster runs — the `devops-engineer` agent

Tabilinks is deployed from the GitOps repository `/home/kovo/IdeaProjects/kovostack-infra-gitops`
(`Kovospace/kovostack-infra-gitops`). **Read it freely; never write to it.** Argo CD reconciles its
`main` continuously with `prune` and `selfHeal`, so a push there is a production deployment with
no approval gate. Every change to it goes through the user-level agent **`devops-engineer`**
(`~/.claude/agents/devops-engineer.md`, which follows that repo's own
`.claude/agents/devops-engineer.md`). It asks the user before every push to `main`.

Where a deployment value belongs decides whether it needs that agent at all:

| The value is… | It lives in | Changed by |
|---|---|---|
| a non-secret setting that differs from the code's default (a path, a URL, an interval) | `applications/<app>/values.yaml`, the `env:` block | `devops-engineer` |
| a secret (API key, signing secret, password) | Infisical, pulled into the Pod through `envFrom` — no manifest change | **the user**, in Infisical. Never in git, never in an agent brief |
| the image tag | `versions/<app>.yaml` | CI, never by hand |
| the migrations init-container version | `versions/new-tab-links-backend-init.yaml` | the backend pipeline; `devops-engineer` only if it cannot |
| equal to the code's default | nowhere — leave it unset | — |

`<app>` is `new-tab-links-backend` or `new-tab-links-frontend`. For the frontend, `env:` becomes
`config.json` at container start, so it is only ever public configuration.

**What to hand it.** It knows Kubernetes, not this application, so a brief names: the app, the
exact variable name, the exact value, **why** that value, and any ordering against a release
("before the backend image with X deploys"). Label it implementation, as with any agent. For
example: *new-tab-links-backend, set `CREEM_CHECKOUT_SUCCESS_PATH=/account?purchase=complete` in
`env:` — where Creem sends a buyer after paying; must land with or after the frontend release
that reads that parameter.*

For this repo it is mostly the last row but one: the backend pipeline pins the migrations image
version when the backend deploys. A migration that must run *before* a backend release is still
released by this repo's own image workflow first.

A new variable in code with a working default needs nothing in the cluster. Say so in the report
rather than asking for a no-op change.

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
| `user_entitlement` | `V10:63` | `V11` — superseded subscription |
| `payment_webhook_event` | `V10:122` | |
| `daily_metric` | `V12:32` | |
| `website_visitor_hash` | `V12:41` | `V14` — dropped; the website deduplicates visits itself |
| `admin_sign_in_lock` | `V13:25` | |

`V1:25` means `sql/V1__initial_schema.sql`, line 25.

## What a delete takes with it

Every foreign key cascades **except one**:

- `app_user` → `user_identity`, `user_device`, `emailed_token`, `single_use_code`,
  `refresh_token`, `environment`, `profile`: `ON DELETE CASCADE`
- `user_device` → `refresh_token`: `CASCADE`
- `profile` → `environment` → `link_group` → `link_subgroup`, `link`: `CASCADE`
- `profile` → `closed_tab`: `CASCADE`
- `app_user` → `user_entitlement`: `CASCADE`
- `daily_metric`: no foreign keys — aggregates, tied to no account
- `admin_sign_in_lock`: no foreign keys — the operator has no account
- **`link_subgroup` → `link`: `ON DELETE SET NULL`.** Deleting a subgroup keeps its links and
  moves them up to the group.

Regenerate the table index with
`grep -nE '^\s*(CREATE TABLE|ALTER TABLE)' sql/*` and the delete rules with
`grep -n REFERENCES sql/*` when a migration is added.
