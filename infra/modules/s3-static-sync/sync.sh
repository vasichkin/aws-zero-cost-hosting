#!/bin/bash
# Publish SOURCE_DIR to s3://BUCKET with `aws s3 sync --delete`, then invalidate CloudFront.
# Used by the module's apply-time provisioner and by `make prod-sync` / `make dev-sync`.
# Env: SOURCE_DIR, BUCKET (required); CACHE_CONTROL, DISTRIBUTION_ID, AWS_REGION (optional).
set -euo pipefail

: "${SOURCE_DIR:?SOURCE_DIR is required}" "${BUCKET:?BUCKET is required}"
CACHE_CONTROL="${CACHE_CONTROL:-public, max-age=3600}"
DISTRIBUTION_ID="${DISTRIBUTION_ID:-}"

# Never open a pager (AWS CLI v2 pipes output through $PAGER, e.g. less, on a terminal).
export AWS_PAGER=""
[ -z "${AWS_REGION:-}" ] || export AWS_REGION

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

echo "==> Syncing $SOURCE_DIR -> s3://$BUCKET"
if ! aws s3 sync "$SOURCE_DIR" "s3://$BUCKET" --delete \
  --exclude ".*" --exclude "*/.*" --cache-control "$CACHE_CONTROL" 2>&1 | tee "$log"; then
  echo "==> Sync status: FAILED (aws s3 sync exited with an error, nothing was invalidated)" >&2
  exit 1
fi

uploaded="$(grep -c '^upload:' "$log" || true)"
deleted="$(grep -c '^delete:' "$log" || true)"

invalidation="skipped (no distribution)"
if [ -n "$DISTRIBUTION_ID" ]; then
  echo "==> Invalidating CloudFront $DISTRIBUTION_ID (/*)"
  if ! id="$(aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" --paths '/*' \
    --query Invalidation.Id --output text)"; then
    echo "==> Sync status: FAILED (files uploaded: $uploaded, deleted: $deleted; CloudFront invalidation failed)" >&2
    exit 1
  fi
  invalidation="$id (InProgress, usually done within a minute)"
fi

echo "==> Sync status: OK - uploaded: $uploaded, deleted: $deleted, invalidation: $invalidation"
