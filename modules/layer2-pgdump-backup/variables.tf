variable "environment" {
  description = "Environment"
  type        = string
}

variable "region" {
  description = "Region for CodeBuild"
  type        = string
  default     = "us-east-1"
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
  description = "Default EventBridge cron expression if DB does not specify one"
  type        = string
  default     = "cron(0 3 ? * SUN *)"
}

variable "target_bucket" {
  description = "Backup account S3 bucket name"
  type        = string
}

variable "backup_account_kms_arn" {
  description = "Backup account KMS key ARN for SSE-KMS"
  type        = string
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
} 