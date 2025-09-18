terraform {
  required_providers { aws = { source = "hashicorp/aws", version = "~> 5.0" } }
}

resource "aws_iam_role" "codebuild_role" {
  name               = "rds-pgdump-codebuild-role-${var.environment}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = var.tags
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "rds-pgdump-codebuild-policy-${var.environment}"
  role = aws_iam_role.codebuild_role.id
  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["rds:DescribeDBInstances", "secretsmanager:GetSecretValue"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:PutObjectAcl"], Resource = ["arn:aws:s3:::${var.target_bucket}/*"] },
      { Effect = "Allow", Action = ["kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"], Resource = var.backup_account_kms_arn }
    ]
  })
}

resource "aws_codebuild_project" "pg_dump_backup" {
  name         = "rds-pgdump-backup-${var.environment}"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable { name = "ENVIRONMENT"         value = var.environment }
    environment_variable { name = "AWS_DEFAULT_REGION"  value = var.region }
    environment_variable { name = "RDS_ENDPOINT"        value = var.rds_endpoint }
    environment_variable { name = "DB_NAME"             value = var.db_name }
    environment_variable { name = "SECRET_ARN"          value = var.secret_arn }
    environment_variable { name = "BACKUP_KMS_KEY_ARN"  value = var.backup_account_kms_arn }
    environment_variable { name = "TARGET_BUCKET"       value = var.target_bucket }
  }

  source { type = "NO_SOURCE" buildspec = file("${path.module}/scripts/buildspec.yml") }

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "rds-pgdump-schedule-${var.environment}"
  schedule_expression = var.backup_schedule
  tags                = var.tags
}

resource "aws_iam_role" "events_invoke_codebuild" {
  name               = "rds-pgdump-events-role-${var.environment}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = var.tags
}

resource "aws_iam_role_policy" "events_invoke_codebuild_policy" {
  name = "rds-pgdump-events-policy-${var.environment}"
  role = aws_iam_role.events_invoke_codebuild.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["codebuild:StartBuild"], Resource = aws_codebuild_project.pg_dump_backup.arn }] })
}

resource "aws_cloudwatch_event_target" "codebuild_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "start-codebuild"
  arn       = aws_codebuild_project.pg_dump_backup.arn
  role_arn  = aws_iam_role.events_invoke_codebuild.arn
} 