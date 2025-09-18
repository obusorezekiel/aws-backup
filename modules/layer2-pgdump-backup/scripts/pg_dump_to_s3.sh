#!/bin/bash
set -euo pipefail

: "${AWS_DEFAULT_REGION:?}"
: "${RDS_ENDPOINT:?}"
: "${DB_NAME:?}"
: "${SECRET_ARN:?}"
: "${TARGET_BUCKET:?}"
: "${BACKUP_KMS_KEY_ARN:?}"

SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --region "$AWS_DEFAULT_REGION" --query SecretString --output text)
USERNAME=$(echo "$SECRET_JSON" | jq -r '.username')
PASSWORD=$(echo "$SECRET_JSON" | jq -r '.password')

STAMP=$(date +%Y%m%d_%H%M%S)
FILE="/tmp/${DB_NAME}_${STAMP}.sql.gz"
PREFIX="layer2/${DB_NAME}/$(date +%Y)/$(date +%m)/$(date +%d)"
KEY="${PREFIX}/${DB_NAME}_${STAMP}.sql.gz"

PGPASSWORD="$PASSWORD" pg_dump -h "$RDS_ENDPOINT" -U "$USERNAME" -d "$DB_NAME" -F p --no-owner --no-privileges --encoding=UTF8 --verbose | gzip -c > "$FILE"

aws s3api put-object \
  --bucket "$TARGET_BUCKET" \
  --key "$KEY" \
  --body "$FILE" \
  --server-side-encryption aws:kms \
  --ssekms-key-id "$BACKUP_KMS_KEY_ARN"

rm -f "$FILE"
echo "Uploaded s3://${TARGET_BUCKET}/${KEY}" 