terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "environment" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "databases" {
  description = "Databases to back up"
  type = list(object({
    rds_endpoint    = string
    db_name         = string
    secret_arn      = string
    backup_schedule = optional(string)
  }))
}

variable "backup_schedule" {
  type    = string
  default = "cron(30 1 * * ? *)"
}

variable "target_bucket" {
  type = string
}

variable "backup_kms_key_arn" {
  type = string
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_iam_role" "codebuild" {
  name               = "rds-pgdump-layer3-codebuild-role-${var.environment}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "codebuild.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = var.tags
}

resource "aws_iam_role_policy" "codebuild" {
  name = "rds-pgdump-layer3-codebuild-policy-${var.environment}"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = "*" },
    { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "*" },
    { Effect = "Allow", Action = ["s3:PutObject","s3:PutObjectAcl","s3:PutObjectRetention","s3:PutObjectLegalHold"], Resource = ["arn:aws:s3:::${var.target_bucket}/*"] },
    { Effect = "Allow", Action = ["kms:Encrypt","kms:GenerateDataKey","kms:DescribeKey"], Resource = var.backup_kms_key_arn }
  ] })
}

locals {
  db_map = { for d in var.databases : d.db_name => d }
}

resource "aws_codebuild_project" "pgdump_l3" {
  for_each     = local.db_map
  name         = "rds-pgdump-layer3-${var.environment}-${each.value.db_name}"
  service_role = aws_iam_role.codebuild.arn

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }
    environment_variable {
      name  = "ENVIRONMENT"
      value = var.environment
    }
    environment_variable {
      name  = "RDS_ENDPOINT"
      value = each.value.rds_endpoint
    }
    environment_variable { 
      name  = "DB_NAME"
      value = each.value.db_name
    }
    environment_variable { 
      name  = "SECRET_ARN"
      value = each.value.secret_arn
    }
    environment_variable { 
      name  = "TARGET_BUCKET"
      value = var.target_bucket
    }
    environment_variable { 
      name  = "BACKUP_KMS_KEY_ARN"
      value = var.backup_kms_key_arn
    }
  }

  source { 
    type      = "NO_SOURCE"
    buildspec = file("${path.module}/scripts/buildspec.yml")
  }

  dynamic "vpc_config" {
    for_each = length(var.subnet_ids) > 0 && length(var.security_group_ids) > 0 && var.vpc_id != "" ? [1] : []
    content {
      vpc_id             = var.vpc_id
      subnets            = var.subnet_ids
      security_group_ids = var.security_group_ids
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "schedule" {
  for_each            = local.db_map
  name                = "rds-pgdump-layer3-schedule-${var.environment}-${each.value.db_name}"
  schedule_expression = coalesce(try(each.value.backup_schedule, null), var.backup_schedule)
  tags                = var.tags
}

resource "aws_iam_role" "events" {
  name               = "rds-pgdump-layer3-events-role-${var.environment}"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "events.amazonaws.com" }, Action = "sts:AssumeRole" }] })
  tags               = var.tags
}

resource "aws_iam_role_policy" "events" {
  name = "rds-pgdump-layer3-events-policy-${var.environment}"
  role = aws_iam_role.events.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = ["codebuild:StartBuild"], Resource = "*" }] })
}

resource "aws_cloudwatch_event_target" "t" {
  for_each  = local.db_map
  rule      = aws_cloudwatch_event_rule.schedule[each.key].name
  target_id = "start-codebuild"
  arn       = aws_codebuild_project.pgdump_l3[each.key].arn
  role_arn  = aws_iam_role.events.arn
} 