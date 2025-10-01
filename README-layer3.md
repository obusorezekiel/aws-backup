### Layer 3 – Implementation (Consolidated Stack)

- Location
  - Backup account module: `infrastructure_consolidation/modules/backup-account-layer3`
  - Source account module: `infrastructure_consolidation/modules/source-account-layer3`
  - Envs:
    - Backup: `infrastructure_consolidation/environments/prod/layer3/backup-account`
    - Source: `infrastructure_consolidation/environments/prod/layer3/source-account`

What it does
- Provides immutable, long-term logical backups using S3 Object Lock (COMPLIANCE mode).
- CodeBuild (source account) runs pg_dump per database and uploads to the backup account bucket with SSE‑KMS.
- The backup bucket policy enforces: HTTPS-only, SSE‑KMS, specific CMK, Object Lock COMPLIANCE, and minimum retention days.
- Object key: `layer3/<db_name>/<YYYY>/<MM>/<DD>/<db_name>_<timestamp>.sql.gz`.

Prerequisites
- Backup account (Melbourne `ap-southeast-4` by default in the env):
  - A customer-managed KMS CMK in `ap-southeast-4` (copy full ARN and Key ID).
  - Deploy the backup-account env to create the S3 bucket with Object Lock; pass the CMK ARN and allowed source role ARNs.
- Source account (e.g., `us-east-1`):
  - CodeBuild projects, IAM role, and EventBridge rules (from the source-account module).
  - Network access to RDS (VPC config if RDS is private).

KMS setup (Backup account, ap-southeast-4)
- Goal: Create a CMK and allow the source CodeBuild role to use it.

- Console
  1. In the backup account, open KMS → Create key → Symmetric, Encrypt and decrypt, Regional.
  2. Add admins (your admin roles). Finish and create alias `alias/rds-backup-layer3-prod`.
  3. Edit key policy → “specify your own key policy” → apply the policy below (replace IDs/roles).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EnableIAMUserPermissions",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::<BACKUP_ACCOUNT_ID>:root" },
      "Action": "kms:*",
      "Resource": "*"
    },
    {
      "Sid": "AllowKeyAdmins",
      "Effect": "Allow",
      "Principal": { "AWS": [
        "arn:aws:iam::<BACKUP_ACCOUNT_ID>:role/<KEY_ADMIN_ROLE>"
      ]},
      "Action": [
        "kms:Create*","kms:Describe*","kms:Enable*","kms:List*","kms:Put*","kms:Update*",
        "kms:Revoke*","kms:Disable*","kms:Get*","kms:Delete*","kms:TagResource",
        "kms:UntagResource","kms:ScheduleKeyDeletion","kms:CancelKeyDeletion"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowSourceCodeBuildUseOfKey",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::<SOURCE_ACCOUNT_ID>:role/rds-pgdump-layer3-codebuild-role-prod" },
      "Action": [ "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey" ],
      "Resource": "*"
    }
  ]
}
```

- CLI (backup account, ap-southeast-4)
```bash
aws kms create-key \
  --region ap-southeast-4 \
  --description "Layer3 CMK for pg_dump backups (Object Lock)" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS > /tmp/k.json

KEY_ID=$(jq -r '.KeyMetadata.KeyId' /tmp/k.json)

aws kms create-alias \
  --region ap-southeast-4 \
  --alias-name alias/rds-backup-layer3-prod \
  --target-key-id "$KEY_ID"

cat > /tmp/kms-policy.json <<'JSON'
{ "Version":"2012-10-17", "Statement":[
  { "Sid":"EnableIAMUserPermissions","Effect":"Allow",
    "Principal":{"AWS":"arn:aws:iam::<BACKUP_ACCOUNT_ID>:root"},
    "Action":"kms:*","Resource":"*" },
  { "Sid":"AllowKeyAdmins","Effect":"Allow",
    "Principal":{"AWS":["arn:aws:iam::<BACKUP_ACCOUNT_ID>:role/<KEY_ADMIN_ROLE>"]},
    "Action":["kms:Create*","kms:Describe*","kms:Enable*","kms:List*","kms:Put*","kms:Update*",
              "kms:Revoke*","kms:Disable*","kms:Get*","kms:Delete*","kms:TagResource",
              "kms:UntagResource","kms:ScheduleKeyDeletion","kms:CancelKeyDeletion"],
    "Resource":"*" },
  { "Sid":"AllowSourceCodeBuildUseOfKey","Effect":"Allow",
    "Principal":{"AWS":"arn:aws:iam::<SOURCE_ACCOUNT_ID>:role/rds-pgdump-layer3-codebuild-role-prod"},
    "Action":["kms:Encrypt","kms:GenerateDataKey","kms:DescribeKey"],
    "Resource":"*" }
]}
JSON

aws kms put-key-policy \
  --region ap-southeast-4 \
  --key-id "$KEY_ID" \
  --policy-name default \
  --policy file:///tmp/kms-policy.json
```

Backup account – Environment config (example tfvars)
```hcl
region                = "ap-southeast-4"
layer3_bucket_name    = "rds-backup-layer3-prod"
kms_key_arn           = "arn:aws:kms:ap-southeast-4:<BACKUP_ACCT_ID>:key/<KEY_ID>"
allowed_source_role_arns = [
  "arn:aws:iam::<SOURCE_ACCOUNT_ID>:role/rds-pgdump-layer3-codebuild-role-prod"
]
```

Source account – Environment config (multi‑DB, example tfvars)
```hcl
region  = "us-east-1"

databases = [
  {
    rds_endpoint    = "db-1.cluster-xxx.us-east-1.rds.amazonaws.com"
    db_name         = "appdb"
    secret_arn      = "arn:aws:secretsmanager:us-east-1:<SRC_ACCT>:secret:appdb"
    # backup_schedule = "cron(0 * * * ? *)" # optional per-DB override
  }
]

target_bucket      = "rds-backup-layer3-prod"                                 # backup account bucket (ap-southeast-4)
backup_kms_key_arn = "arn:aws:kms:ap-southeast-4:<BACKUP_ACCT_ID>:key/<KEY_ID>" # backup account CMK
backup_schedule    = "cron(30 1 * * ? *)"                                      # default/fallback schedule

# If RDS is private
# vpc_id             = "vpc-xxxxxxxx"
# subnet_ids         = ["subnet-aaa","subnet-bbb"]
# security_group_ids = ["sg-xxxxxxxx"]
```

Deploy order
1) Backup account
- cd `infrastructure_consolidation/environments/prod/layer3/backup-account`
- `terraform init && terraform apply`

2) Source account
- cd `infrastructure_consolidation/environments/prod/layer3/source-account`
- `terraform init && terraform apply`

Run a backup now (per DB)
- Project: `rds-pgdump-layer3-prod-<db_name>`
- Start: `aws codebuild start-build --project-name rds-pgdump-layer3-prod-<db_name>`
- Check: `aws codebuild batch-get-builds --ids <build-id> --query 'builds[0].buildStatus'`

Verify in S3 (Backup account)
- Listing: `aws s3 ls s3://<bucket>/layer3/<db_name>/<YYYY>/<MM>/<DD>/`
- Encryption: `aws s3api head-object --bucket <bucket> --key layer3/<db>/<YYYY>/<MM>/<DD>/<db>_<ts>.sql.gz | jq -r '.ServerSideEncryption, .SSEKMSKeyId'`
- Object Lock: `aws s3api get-object-attributes --bucket <bucket> --key layer3/<db>/<YYYY>/<MM>/<DD>/<db>_<ts>.sql.gz --object-attributes ObjectLock | jq .` (expect `ObjectLockMode=COMPLIANCE` and a future `RetainUntilDate`)

Notes
- Bucket policy is created by Terraform and enforces SSE‑KMS with your CMK, HTTPS-only, Object Lock COMPLIANCE, and minimum retention. Writes are only allowed from `allowed_source_role_arns`.
- The CMK region must match the bucket region (`ap-southeast-4`). The CodeBuild uploads can come from any region as long as policies allow the role.
- Ensure the source CodeBuild role name/ARN in both: KMS key policy (backup account) and `allowed_source_role_arns` (bucket policy input) exactly match.
- If builds timeout connecting to RDS, add VPC config and allow SG ingress to port 5432 from the CodeBuild SG.
- Ensure CodeBuild installs a pg_dump version ≥ your PostgreSQL server version (handled in the module buildspec). 