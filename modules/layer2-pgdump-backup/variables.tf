variable "environment" {
  description = "Environment"
  type        = string
}

variable "region" {
  description = "Region for CodeBuild"
  type        = string
  default     = "us-east-1"
}

variable "rds_endpoint" {
  description = "RDS endpoint"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "secret_arn" {
  description = "Secrets Manager ARN with {username,password}"
  type        = string
}

variable "target_bucket" {
  description = "Backup account S3 bucket name"
  type        = string
}

variable "backup_account_kms_arn" {
  description = "Backup account KMS key ARN for SSE-KMS"
  type        = string
}

variable "backup_schedule" {
  description = "EventBridge cron expression"
  type        = string
  default     = "cron(0 3 ? * SUN *)"
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
} 