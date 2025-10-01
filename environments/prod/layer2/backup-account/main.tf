terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  alias  = "backup"
  region = var.region
  profile    = var.aws_profile
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  token      = var.aws_session_token
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "aws_profile" {
  type    = string
  default = null
}

variable "aws_access_key" {
  type      = string
  default   = null
  sensitive = true
}

variable "aws_secret_key" {
  type      = string
  default   = null
  sensitive = true
}

variable "aws_session_token" {
  type      = string
  default   = null
  sensitive = true
}

variable "bucket_name" {
  type = string
}

variable "kms_alias" {
  type    = string
  default = "alias/rds-backup-layer2-prod"
}

variable "kms_allowed_principals" {
  type = list(string)
}

variable "s3_allowed_writer_role_arns" {
  type = list(string)
}

variable "admin_role_arns" {
  type    = list(string)
  default = []
}

variable "transition_to_glacier_days" {
  type    = number
  default = 30
}

variable "transition_to_deep_days" {
  type    = number
  default = 120
}

variable "expire_after_days" {
  type    = number
  default = 2555
}

locals {
  tags = {
    Environment = "prod"
    Layer       = "Layer2"
    ManagedBy   = "terraform"
    Scope       = "backup"
  }
}

module "l2_backup_account" {
  source    = "../../../../../infrastructure_consolidation/modules/backup-account-layer2"
  providers = { aws = aws.backup }

  bucket_name                  = var.bucket_name
  kms_alias                    = var.kms_alias
  kms_allowed_principals       = var.kms_allowed_principals
  s3_allowed_writer_role_arns  = var.s3_allowed_writer_role_arns
  admin_role_arns              = var.admin_role_arns
  transition_to_glacier_days   = var.transition_to_glacier_days
  transition_to_deep_days      = var.transition_to_deep_days
  expire_after_days            = var.expire_after_days
  tags                         = local.tags
} 