# Instaclean Production

Database checkpoint and backups for the Instaclean production Supabase project.

## Contents

| File / path | Description |
|-------------|-------------|
| `schema.sql` | Full database schema dump |
| `roles.sql` | Database roles and grants |
| `scripts/dump_functions_triggers.sql` | Helper query for functions and triggers |
| `.github/workflows/backup.yml` | Scheduled and on-push backup workflow |

## Backups

GitHub Actions runs daily (midnight UTC) and on pushes to `main` to refresh schema dumps and upload full backups to R2 when enabled via repository secrets.
