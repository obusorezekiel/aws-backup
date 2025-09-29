terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "target_bucket" {
  type = string
}

variable "backup_account_kms_arn" {
  type = string
}

variable "backup_schedule" {
  type    = string
  default = "cron(0 3 ? * SUN *)"
}

variable "databases" {
  type = list(object({
    rds_endpoint    = string
    db_name         = string
    secret_arn      = string
    backup_schedule = optional(string)
  }))
}

locals {
  tags = {
    Environment = var.environment
    Layer       = "Layer2"
    ManagedBy   = "terraform"
  }
}

module "layer2" {
  source                 = "../../../../infrastructure_consolidation/modules/layer2-pgdump-backup"
  environment            = var.environment
  region                 = var.region
  databases              = var.databases   # <— add this
  target_bucket          = var.target_bucket
  backup_account_kms_arn = var.backup_account_kms_arn
  backup_schedule        = var.backup_schedule
  tags                   = local.tags
}