terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

variable "bucket_name" {
  type = string
}

variable "kms_alias" {
  type    = string
  default = "alias/rds-backup-layer2-prod"
}

variable "kms_multi_region" {
  description = "Create the KMS key as a multi-Region primary key"
  type        = bool
  default     = true
}

variable "kms_allowed_principals" {
  description = "AWS principal ARNs allowed to use the CMK (can include account root and/or specific roles)"
  type        = list(string)
  default     = []
}

variable "s3_allowed_writer_role_arns" {
  description = "IAM role ARNs in source account allowed to write to the bucket"
  type        = list(string)
  default     = []
}

variable "admin_role_arns" {
  description = "Backup account admin role ARNs for KMS administration"
  type        = list(string)
  default     = []
}

variable "transition_to_glacier_days" {
  type    = number
  default = 30
}

variable "transition_to_deep_days" {
  type    = number
  default = 120
  validation {
    condition     = var.transition_to_deep_days >= var.transition_to_glacier_days + 90
    error_message = "transition_to_deep_days must be at least 90 days greater than transition_to_glacier_days."
  }
}

variable "expire_after_days" {
  type    = number
  default = 2555
}

variable "tags" {
  type    = map(string)
  default = {}
} 