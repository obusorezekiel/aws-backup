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

STAMP=$(date -u +%Y%m%d_%H%M%S)
KEY="layer3/${DB_NAME}/$(date -u +%Y)/$(date -u +%m)/$(date -u +%d)/${DB_NAME}_${STAMP}.sql.gz"
FILE="/tmp/${DB_NAME}_${STAMP}.sql.gz"
RETENTION=$(date -u -d "+7 years" +"%Y-%m-%dT%H:%M:%SZ")

PGPASSWORD="$PASSWORD" pg_dump -h "$RDS_ENDPOINT" -U "$USERNAME" -d "$DB_NAME" -F p --no-owner --no-privileges | gzip -c > "$FILE"

aws s3api put-object \
  --bucket "$TARGET_BUCKET" \
  --key "$KEY" \
  --body "$FILE" \
  --server-side-encryption aws:kms \
  --ssekms-key-id "$BACKUP_KMS_KEY_ARN" \
  --object-lock-mode COMPLIANCE \
  --object-lock-retain-until-date "$RETENTION"

rm -f "$FILE"
echo "Uploaded s3://${TARGET_BUCKET}/${KEY} with Object Lock until $RETENTION" 