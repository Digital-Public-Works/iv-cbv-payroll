
locals {
  tf_state_bucket_name = "${module.project_config.project_name}-${module.project_config.log_archive_account_id}-${module.project_config.default_region}-tf"

  tags = merge(module.project_config.default_tags, {
    description = "Log-archive account - Terraform backend and GitHub OIDC provider and account-wide S3 guardrails"
  })
}

terraform {
  required_version = "~>1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.35.0, < 6.0.0"
    }
  }

  backend "s3" {
    encrypt = "true"
  }
}

provider "aws" {
  region = module.project_config.default_region

  # Refuse to run against any other account.
  allowed_account_ids = [module.project_config.log_archive_account_id]

  default_tags {
    tags = local.tags
  }
}

module "project_config" {
  source = "../project-config"
}

module "backend" {
  source = "../modules/terraform-backend-s3"
  name   = local.tf_state_bucket_name
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["0000000000000000000000000000000000000000"]
}

# backstop - don't make bucket's public
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
