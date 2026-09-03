# Instaclean Production

Database checkpoint and backups for the Instaclean production Supabase project.

## Contents

| File / path | Description |
|-------------|-------------|
| `schema.sql` | Supabase-filtered database schema dump |
| `roles.sql` | Database roles and grants |
| `scripts/dump_functions_triggers.sql` | Helper query for functions and triggers |
| `.github/workflows/backup.yml` | Scheduled, manual, and validation backup workflow |

## Backups

GitHub Actions runs daily at midnight UTC and can also be started manually. Full scheduled/manual backups are uploaded to the private Cloudflare R2 backup bucket when enabled through repository secrets.

Each successful full backup is stored under:

```text
YYYY-MM-DD/<github-run-id>/
```

The backup set contains:

```text
schema.sql.gz
roles.sql.gz
functions_triggers.sql.gz
config_data.sql.gz
data.sql.gz
full.dump
full.dump.list
manifest.json
checksums.sha256
```

### `data.sql.gz`

`data.sql.gz` is the portable application-data dump created with `supabase db dump --data-only --use-copy`.

The Supabase CLI intentionally filters Supabase-managed schemas such as `auth`, `storage`, and extension-owned schemas. This file is therefore useful for restoring Instaclean application data alongside the filtered schema, but it is not the complete database archive.

### `full.dump`

`full.dump` is a PostgreSQL custom-format archive produced with raw `pg_dump`. It captures all non-system schemas visible to the backup connection, including Supabase-managed database data such as `auth` and `storage` metadata.

This archive is intended for disaster recovery and migration analysis. Do not restore it blindly into Fly Managed Postgres because it also contains Supabase-specific objects and extension-owned database structures. Inspect and selectively restore it with `pg_restore`.

Example inspection:

```bash
pg_restore --list full.dump
```

Example data-only restore into a prepared target database:

```bash
pg_restore \
  --data-only \
  --no-owner \
  --no-privileges \
  --dbname "$TARGET_DATABASE_URL" \
  full.dump
```

For the Supabase → Fly migration, restore only after the target schema, extensions, identity strategy, and Supabase-specific compatibility work have been prepared.

## R2 latest pointer

After every successful full backup upload, the workflow updates:

```text
latest.json
```

The pointer contains the latest full-backup prefix and paths to `manifest.json`, `data.sql.gz`, and `full.dump`. It is written only after all required full-backup artifacts upload successfully.

## Validation

A full backup fails rather than publishing a false-success snapshot when:

- `data.sql.gz` is invalid gzip
- the portable dump contains no `COPY` sections
- `full.dump` contains no PostgreSQL `TABLE DATA` entries
- required archive entries for `auth.users`, `public.bookings`, or `public.users` are missing
- a required full-backup artifact is missing or empty

`checksums.sha256` records SHA-256 hashes for the backup artifacts, and `manifest.json` records the source PostgreSQL version, GitHub run metadata, artifact roles, and whether each artifact contains row data.

## Security

Production row data and authentication records are never committed to this public GitHub repository. Full data artifacts exist only on the ephemeral GitHub Actions runner and in the configured private R2 bucket.

Keep the R2 bucket private and keep its credentials in GitHub Actions secrets. Treat `full.dump` as highly sensitive because it can include authentication records and other production data.
