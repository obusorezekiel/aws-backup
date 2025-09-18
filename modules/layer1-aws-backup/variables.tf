variable "environment" {
  description = "Environment"
  type        = string
}

variable "region" {
  description = "Region"
  type        = string
}

variable "backup_schedule" {
  description = "Cron"
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "retention_days" {
  description = "Retention days"
  type        = number
  default     = 28
}

variable "rds_instance_arns" {
  description = "RDS ARNs"
  type        = list(string)
}

variable "kms_deletion_window" {
  description = "KMS deletion window"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "Logs retention"
  type        = number
  default     = 30
}

variable "sns_topic_arn" {
  description = "SNS topic ARN"
  type        = string
  default     = null
}

variable "enable_on_demand_backup" {
  description = "Enable on-demand"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags"
  type        = map(string)
  default     = {}
} 