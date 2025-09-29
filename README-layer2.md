### Layer 2 – Implementation (Consolidated Stack)

- Location
  - Module: `infrastructure_consolidation/modules/layer2-pgdump-backup`
  - Env: `infrastructure_consolidation/environments/prod/layer2`

What it does
- EventBridge triggers a CodeBuild project per database.
- CodeBuild fetches creds from Secrets Manager, runs pg_dump, gzips, and uploads to S3 with SSE‑KMS.
- Object key: `layer2/<db_name>/<YYYY>/<MM>/<DD>/<db_name>_<timestamp>.sql.gz`.

Prerequisites (Backup account)
- S3 bucket in us‑east‑1 (example: `rds-backup-layer2-prod`).
- Customer-managed KMS CMK in us‑east‑1 (copy full ARN).
- KMS key policy must allow the source CodeBuild role to use the key.
- S3 bucket policy must allow the source CodeBuild role to put objects and must enforce SSE‑KMS with the specific CMK.

Working S3 bucket policy (replace with your values)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowSourceCodeBuildPut",
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::<SOURCE_ACCOUNT_ID>:role/rds-pgdump-codebuild-role-prod" },
      "Action": [ "s3:PutObject", "s3:PutObjectAcl" ],
      "Resource": "arn:aws:s3:::rds-backup-layer2-prod/*"
    },
    {
      "Sid": "RequireKmsSse",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::rds-backup-layer2-prod/*",
      "Condition": {
        "StringNotEquals": { "s3:x-amz-server-side-encryption": "aws:kms" }
      }
    },
    {
      "Sid": "RequireSpecificKmsKey",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::rds-backup-layer2-prod/*",
      "Condition": {
        "StringNotEquals": {
          "s3:x-amz-server-side-encryption-aws-kms-key-id": [
            "arn:aws:kms:us-east-1:<BACKUP_ACCOUNT_ID>:key/<CMK_KEY_ID>",
            "<CMK_KEY_ID>"
          ]
        }
      }
    }
  ]
}
```

KMS key policy (Backup account CMK)
```json
{
  "Sid": "AllowSourceCodeBuildUseOfKey",
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::<SOURCE_ACCOUNT_ID>:role/rds-pgdump-codebuild-role-prod" },
  "Action": [ "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey" ],
  "Resource": "*"
}
```

Source account – Configure
- `terraform.tfvars` (multi‑DB):
```hcl
environment            = "prod"
region                 = "us-east-1"

databases = [
  {
    rds_endpoint    = "db-1.cluster-xxx.us-east-1.rds.amazonaws.com"
    db_name         = "appdb"
    secret_arn      = "arn:aws:secretsmanager:us-east-1:<SRC_ACCT>:secret:appdb"
    # backup_schedule = "cron(0 * * * ? *)" # optional per-DB override
  },
  {
    rds_endpoint    = "db-2.cluster-yyy.us-east-1.rds.amazonaws.com"
    db_name         = "dw"
    secret_arn      = "arn:aws:secretsmanager:us-east-1:<SRC_ACCT>:secret:dw"
  }
]

target_bucket          = "rds-backup-layer2-prod"                              # backup account bucket (us-east-1)
backup_account_kms_arn = "arn:aws:kms:us-east-1:<BACKUP_ACCT_ID>:key/<CMK_ID>" # backup account CMK
backup_schedule        = "cron(0 3 ? * SUN *)"                                 # default/fallback schedule
```

Deploy
- cd `infrastructure_consolidation/environments/prod/layer2`
- `terraform init && terraform apply`

Run a backup now (per DB)
- Project: `rds-pgdump-backup-prod-<db_name>`
- Start: `aws codebuild start-build --project-name rds-pgdump-backup-prod-<db_name>`
- Check: `aws codebuild batch-get-builds --ids <build-id> --query 'builds[0].buildStatus'`

Verify in S3 (Backup account)
- `aws s3 ls s3://<bucket>/layer2/<db_name>/<YYYY>/<MM>/<DD>/`
- `aws s3api head-object --bucket <bucket> --key layer2/<db>/<YYYY>/<MM>/<DD>/<db>_<ts>.sql.gz`
  - Expect `ServerSideEncryption=aws:kms` and `SSEKMSKeyId=<backup CMK ARN or KeyId>`.

Networking (private RDS)
- Add VPC config to the module (or env) with `subnet_ids`, `security_group_ids`, `vpc_id`.
- RDS SG inbound: allow TCP 5432 from the CodeBuild SG.

Notes
- Frequency: per‑DB via `databases[].backup_schedule` or default `backup_schedule`; EventBridge supports every minute—use something ≥ pg_dump duration.
- Costs: more frequent backups = more CodeBuild minutes, KMS requests, S3 storage.

### KMS setup (Backup account, us-east-1)

- Create a customer-managed CMK and allow the source account’s CodeBuild role to encrypt with it.

- Console
  1. In the backup account, go to KMS → Create key → Symmetric, Encrypt and decrypt, Regional.
  2. Set administrators (your admin role(s)).
  3. Finish, then create alias `alias/rds-backup-layer2-prod`.
  4. Edit key policy → switch to “specify your own key policy” → use the policy below (replace IDs).

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
      "Principal": { "AWS": "arn:aws:iam::<SOURCE_ACCOUNT_ID>:role/rds-pgdump-codebuild-role-prod" },
      "Action": [ "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey" ],
      "Resource": "*"
    }
  ]
}
```

- CLI (backup account, us-east-1)
```bash
aws kms create-key \
  --region us-east-1 \
  --description "Layer2 CMK for pg_dump backups" \
  --key-usage ENCRYPT_DECRYPT \
  --origin AWS_KMS > /tmp/k.json

KEY_ID=$(jq -r '.KeyMetadata.KeyId' /tmp/k.json)

aws kms create-alias \
  --region us-east-1 \
  --alias-name alias/rds-backup-layer2-prod \
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
    "Principal":{"AWS":"arn:aws:iam::<SOURCE_ACCOUNT_ID>:role/rds-pgdump-codebuild-role-prod"},
    "Action":["kms:Encrypt","kms:GenerateDataKey","kms:DescribeKey"],
    "Resource":"*" }
]}
JSON

aws kms put-key-policy \
  --region us-east-1 \
  --key-id "$KEY_ID" \
  --policy-name default \
  --policy file:///tmp/kms-policy.json
```

- Hook into Terraform
  - Set in the source env tfvars: `backup_account_kms_arn = "arn:aws:kms:us-east-1:<BACKUP_ACCOUNT_ID>:key/<KEY_ID>"`.
  - Ensure the backup bucket policy enforces SSE-KMS with this CMK and allows the source CodeBuild role (see policy above).