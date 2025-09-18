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

variable "rds_endpoint" {
  type = string
}

variable "db_name" {
  type = string
}

variable "secret_arn" {
  type = string
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

locals {
  tags = {
    Environment = var.environment
    Layer       = "Layer2"
    ManagedBy   = "terraform"
  }
}

module "layer2" {
  source = "../../../../infrastructure_consolidation/modules/layer2-pgdump-backup"

  environment            = var.environment
  region                 = var.region
  rds_endpoint           = var.rds_endpoint
  db_name                = var.db_name
  secret_arn             = var.secret_arn
  target_bucket          = var.target_bucket
  backup_account_kms_arn = var.backup_account_kms_arn
  backup_schedule        = var.backup_schedule
  tags                   = local.tags
} 