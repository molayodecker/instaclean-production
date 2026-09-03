#!/usr/bin/env bash
set -euo pipefail

: "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID is required}"
: "${R2_BUCKET_NAME:?R2_BUCKET_NAME is required}"
: "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID is required}"
: "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY is required}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required" >&2
  exit 1
fi

export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
DESTINATION="${1:-./restore/latest}"
LATEST_FILE="$DESTINATION/latest.json"

mkdir -p "$DESTINATION/exports"

aws s3 cp \
  "s3://$R2_BUCKET_NAME/latest.json" \
  "$LATEST_FILE" \
  --endpoint-url "$ENDPOINT"

PREFIX="$(python3 - "$LATEST_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
prefix = data.get("prefix")
if not prefix or prefix.startswith("/") or ".." in prefix.split("/"):
    raise SystemExit("latest.json does not contain a safe backup prefix")
print(prefix)
PY
)"

REMOTE_PREFIX="s3://$R2_BUCKET_NAME/$PREFIX"

echo "Downloading backup: $REMOTE_PREFIX"

aws s3 cp "$REMOTE_PREFIX/schema.sql.gz" "$DESTINATION/schema.sql.gz" --endpoint-url "$ENDPOINT"
aws s3 cp "$REMOTE_PREFIX/roles.sql.gz" "$DESTINATION/roles.sql.gz" --endpoint-url "$ENDPOINT"
aws s3 cp "$REMOTE_PREFIX/functions_triggers.sql.gz" "$DESTINATION/exports/functions_triggers.sql.gz" --endpoint-url "$ENDPOINT"
aws s3 cp "$REMOTE_PREFIX/config_data.sql.gz" "$DESTINATION/exports/config_data.sql.gz" --endpoint-url "$ENDPOINT"
aws s3 cp "$REMOTE_PREFIX/data.sql.gz" "$DESTINATION/data.sql.gz" --endpoint-url "$ENDPOINT"
aws s3 cp "$REMOTE_PREFIX/full.dump" "$DESTINATION/full.dump" --endpoint-url "$ENDPOINT"
aws s3 cp "$REMOTE_PREFIX/full.dump.list" "$DESTINATION/full.dump.list" --endpoint-url "$ENDPOINT"
aws s3 cp "$REMOTE_PREFIX/manifest.json" "$DESTINATION/manifest.json" --endpoint-url "$ENDPOINT"
aws s3 cp "$REMOTE_PREFIX/checksums.sha256" "$DESTINATION/checksums.sha256" --endpoint-url "$ENDPOINT"

(
  cd "$DESTINATION"
  sha256sum -c checksums.sha256
)

gzip -t "$DESTINATION/schema.sql.gz"
gzip -t "$DESTINATION/roles.sql.gz"
gzip -t "$DESTINATION/exports/functions_triggers.sql.gz"
gzip -t "$DESTINATION/exports/config_data.sql.gz"
gzip -t "$DESTINATION/data.sql.gz"

if command -v pg_restore >/dev/null 2>&1; then
  pg_restore --list "$DESTINATION/full.dump" >/dev/null
else
  echo "pg_restore not installed; skipped custom archive validation" >&2
fi

echo "Backup downloaded and checksum-verified at: $DESTINATION"
echo "Manifest: $DESTINATION/manifest.json"
echo "Portable application data: $DESTINATION/data.sql.gz"
echo "Complete PostgreSQL archive: $DESTINATION/full.dump"
