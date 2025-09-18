terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  alias  = "backup"
  region = var.region
}

variable "region" {
  type    = string
  default = "ap-southeast-4"
}

variable "layer3_bucket_name" {
  type = string
}

variable "kms_key_arn" {
  type = string
}

variable "allowed_source_role_arns" {
  type = list(string)
}

locals {
  tags = {
    Environment = "prod"
    Layer       = "Layer3"
    ManagedBy   = "terraform"
    Scope       = "backup"
  }
}

module "l3_backup_account" {
  source = "../../../../../infrastructure_consolidation/modules/backup-account-layer3"
  providers = { aws = aws.backup }

  layer3_bucket_name         = var.layer3_bucket_name
  kms_key_arn                = var.kms_key_arn
  allowed_source_role_arns   = var.allowed_source_role_arns
  transition_to_glacier_days = 30
  transition_to_deep_days    = 90
  expire_after_days          = 2555
  tags                       = local.tags
} 