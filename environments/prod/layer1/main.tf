terraform {
  required_providers {
    aws = { source = "hashicorp/aws", 
    version = "~> 5.0" 
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Layer       = "Layer1"
      ManagedBy   = "terraform"
    }
  }
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "rds_instance_arns" {
  type = list(string)
}

variable "sns_topic_arn" {
  type    = string
  default = null
}

locals {
  tags = {
    Environment = var.environment
    Layer       = "Layer1"
    ManagedBy   = "terraform"
  }
}

module "layer1" {
  source = "../../../../infrastructure_consolidation/modules/layer1-aws-backup"

  environment         = var.environment
  region              = var.region
  backup_schedule     = "cron(0 2 * * ? *)"
  retention_days      = 28
  rds_instance_arns   = var.rds_instance_arns
  kms_deletion_window = 30
  log_retention_days  = 30
  sns_topic_arn       = var.sns_topic_arn
  enable_on_demand_backup = true
  tags = local.tags
} 