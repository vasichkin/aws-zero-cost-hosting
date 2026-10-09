terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "opentofu"
  })
  admin_origin = "http://localhost:5173"
}

module "site_bucket" {
  source = "../../modules/s3-bucket"

  bucket_name          = "${local.name_prefix}-site"
  enable_cors          = true
  cors_allowed_origins = [local.admin_origin]
  tags                 = local.common_tags
}

module "website_sync" {
  source = "../../modules/s3-static-sync"

  bucket_id  = module.site_bucket.bucket_id
  source_dir = "${path.module}/../../../website"
  tags       = local.common_tags
}

module "metadata_table" {
  source = "../../modules/dynamodb"

  table_name                    = "${local.name_prefix}-metadata"
  enable_point_in_time_recovery = false
  tags                          = local.common_tags
}

module "cognito" {
  source = "../../modules/cognito"

  user_pool_name      = "${local.name_prefix}-admins"
  admin_callback_urls = ["http://localhost:5173/admin/callback"]
  admin_logout_urls   = ["http://localhost:5173/admin"]
  tags                = local.common_tags
}

module "api" {
  source = "../../modules/api"

  api_name             = "${local.name_prefix}-api"
  enable_contact_route = false
  cors_allow_origins   = [local.admin_origin]
  cognito_user_pool_id = module.cognito.user_pool_id
  cognito_client_id    = module.cognito.admin_client_id
  tags                 = local.common_tags
}

module "cloudfront" {
  source = "../../modules/cloudfront-app"

  distribution_name = "${local.name_prefix}-app"
  api_origin_domain = replace(module.api.api_endpoint, "https://", "")

  site_bucket = {
    id                       = module.site_bucket.bucket_id
    arn                      = module.site_bucket.bucket_arn
    regional_domain_name     = module.site_bucket.bucket_regional_domain_name
    origin_access_control_id = module.site_bucket.origin_access_control_id
  }

  tags = local.common_tags

  depends_on = [module.api]
}
