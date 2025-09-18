terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.region
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

variable "backup_kms_key_arn" {
  type = string
}

variable "backup_schedule" {
  type    = string
  default = "cron(30 1 * * ? *)"
}

variable "subnet_ids" {
  type    = list(string)
  default = []
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

locals {
  tags = {
    Environment = "prod"
    Layer       = "Layer3"
    ManagedBy   = "terraform"
    Scope       = "source"
  }
}

module "l3_source" {
  source = "../../../../../infrastructure_consolidation/modules/source-account-layer3"

  environment        = "prod"
  region             = var.region
  rds_endpoint       = var.rds_endpoint
  db_name            = var.db_name
  secret_arn         = var.secret_arn
  target_bucket      = var.target_bucket
  backup_kms_key_arn = var.backup_kms_key_arn
  backup_schedule    = var.backup_schedule
  subnet_ids         = var.subnet_ids
  security_group_ids = var.security_group_ids
  tags               = local.tags
} 