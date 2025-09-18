# Consolidated Terraform for Layer 1, 2, and 3

This directory organizes all three layers into one codebase while keeping separate stacks/state per layer and account boundary.

## Layout

```
infrastructure_consolidation/
  environments/
    prod/
      layer1/                 # Layer 1 in source account/region
        main.tf
        terraform.tfvars.example
      layer2/                 # Layer 2 in source account/region (cross-account to backup)
        main.tf
        terraform.tfvars.example
      layer3/
        backup-account/       # Layer 3 bucket/policy in backup account (ap-southeast-4)
          main.tf
          terraform.tfvars.example
        source-account/       # Layer 3 codebuild/schedule in source account/region
          main.tf
          terraform.tfvars.example
```

Each stack references the modules already defined in this repo:
- Layer 1: `infrastructure/terraform/modules/layer1-aws-backup`
- Layer 2: `infrastructure_layer2/terraform/modules/layer2-pgdump-backup`
- Layer 3 (backup-account): `infrastructure_layer3/terraform/modules/backup-account-layer3`
- Layer 3 (source-account): `infrastructure_layer3/terraform/modules/source-account-layer3`

## Providers & Accounts
- Layer 1: default provider = source account, source region.
- Layer 2: default provider = source account, source region.
- Layer 3:
  - backup-account stack uses an aliased provider for the backup account (ap-southeast-4).
  - source-account stack uses default provider for source account/region.

## Apply Order
1) Layer 3 backup-account (creates bucket/policy/KMS usage in backup account)
2) Layer 2 (uses bucket & KMS ARN from backup account)
3) Layer 3 source-account (if not done alongside 2)
4) Layer 1 (independent, short-term operational)

## Notes
- Maintain separate Terraform state per stack (run `terraform init/plan/apply` in each folder).
- Configure AWS credentials/assumed roles per account as needed.
- Fill each `terraform.tfvars` from the examples. 