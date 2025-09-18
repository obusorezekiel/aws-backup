# Layer 1: AWS Backup - Short-Term (28 days)
# This module implements AWS Backup for operational recovery

# Data source to get current AWS account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}

# KMS Key for backup vault encryption
resource "aws_kms_key" "backup_vault_key" {
  description             = "KMS key for AWS Backup vault encryption (${var.environment})"
  deletion_window_in_days = var.kms_deletion_window
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name        = "rds-backup-vault-key-${var.environment}"
    Purpose     = "AWS Backup Vault Encryption"
    Layer       = "Layer1"
    Environment = var.environment
  })
}

# KMS Key Alias
resource "aws_kms_alias" "backup_vault_key_alias" {
  name          = "alias/rds-backup-vault-${var.environment}"
  target_key_id = aws_kms_key.backup_vault_key.key_id
}

# IAM Role for AWS Backup Service
resource "aws_iam_role" "aws_backup_role" {
  name = "rds-backup-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name        = "rds-backup-role-${var.environment}"
    Purpose     = "AWS Backup Service Role"
    Layer       = "Layer1"
    Environment = var.environment
  })
}

# Attach AWS managed policy for backup service
resource "aws_iam_role_policy_attachment" "aws_backup_service_role_policy" {
  role       = aws_iam_role.aws_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

# Attach AWS managed policy for restore
resource "aws_iam_role_policy_attachment" "aws_backup_service_role_policy_for_restore" {
  role       = aws_iam_role.aws_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

# Custom policy for additional permissions
resource "aws_iam_role_policy" "aws_backup_custom_policy" {
  name = "rds-backup-custom-policy-${var.environment}"
  role = aws_iam_role.aws_backup_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = aws_kms_key.backup_vault_key.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Backup Vault
resource "aws_backup_vault" "main" {
  name        = "rds-backup-vault-${var.environment}"
  kms_key_arn = aws_kms_key.backup_vault_key.arn

  tags = merge(var.tags, {
    Name        = "rds-backup-vault-${var.environment}"
    Purpose     = "AWS Backup Vault for RDS Snapshots"
    Layer       = "Layer1"
    Environment = var.environment
    Retention   = "28-days"
  })
}

# Backup Plan
resource "aws_backup_plan" "rds_operational" {
  name = "rds-operational-backup-${var.environment}"

  rule {
    rule_name         = "daily_rds_backup"
    target_vault_name = aws_backup_vault.main.name
    schedule          = var.backup_schedule

    lifecycle {
      cold_storage_after = 0
      delete_after       = var.retention_days
    }

    recovery_point_tags = merge(var.tags, {
      Name        = "rds-backup-${var.environment}"
      Purpose     = "Daily RDS Operational Backup"
      Layer       = "Layer1"
      Environment = var.environment
    })
  }

  tags = merge(var.tags, {
    Name        = "rds-operational-backup-${var.environment}"
    Purpose     = "AWS Backup Plan for RDS"
    Layer       = "Layer1"
    Environment = var.environment
  })
}

# Backup Selection - RDS Instances
resource "aws_backup_selection" "rds_instances" {
  iam_role_arn = aws_iam_role.aws_backup_role.arn
  name         = "rds-selection-${var.environment}"
  plan_id      = aws_backup_plan.rds_operational.id

  resources = var.rds_instance_arns

  condition {
    string_equals {
      key   = "aws:ResourceTag/BackupEnabled"
      value = "true"
    }
  }

  condition {
    string_equals {
      key   = "aws:ResourceTag/Environment"
      value = var.environment
    }
  }
}

# CloudWatch Alarms for backup monitoring
resource "aws_cloudwatch_metric_alarm" "backup_failed" {
  alarm_name          = "rds-backup-failed-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors failed backup jobs"
  alarm_actions       = var.sns_topic_arn != null ? [var.sns_topic_arn] : []

  dimensions = {
    BackupVaultName = aws_backup_vault.main.name
  }

  tags = merge(var.tags, {
    Name        = "rds-backup-failed-alarm-${var.environment}"
    Purpose     = "Monitor Failed Backup Jobs"
    Layer       = "Layer1"
    Environment = var.environment
  })
}

# Optional: On-demand backup for testing
resource "aws_backup_plan" "on_demand" {
  count = var.enable_on_demand_backup ? 1 : 0
  name  = "rds-on-demand-backup-${var.environment}"

  rule {
    rule_name         = "on_demand_rule"
    target_vault_name = aws_backup_vault.main.name
    schedule          = "cron(0 12 1 1 ? *)"  # Once a year for testing

    lifecycle {
      cold_storage_after = 0
      delete_after       = 7  # Keep on-demand backups for 7 days
    }

    recovery_point_tags = merge(var.tags, {
      Name        = "rds-on-demand-backup-${var.environment}"
      Purpose     = "On-Demand Backup for Testing"
      Layer       = "Layer1"
      Environment = var.environment
      Type        = "OnDemand"
    })
  }

  tags = merge(var.tags, {
    Name        = "rds-on-demand-backup-${var.environment}"
    Purpose     = "On-Demand Backup Plan"
    Layer       = "Layer1"
    Environment = var.environment
  })
} 