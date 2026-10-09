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

  # Bucket/table/region supplied via backend.hcl at init (see backend.hcl.example).
  backend "s3" {
    key     = "prod/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  # Lambda function names disallow dots; project_name may contain one (e.g. a domain like "buhaj.eu").
  name_prefix_safe = replace(local.name_prefix, ".", "-")
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "opentofu"
  })
  www_domain         = "www.${var.domain_name}"
  site_origin        = "https://${var.domain_name}"
  www_origin         = "https://${local.www_domain}"
  site_origins       = [local.site_origin, local.www_origin]
  use_custom_domain  = var.acm_wait_for_validation
  cloudfront_aliases = local.use_custom_domain ? [var.domain_name, local.www_domain] : []
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "publish_lambda" {
  statement {
    sid    = "DynamoDBAccess"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
      "dynamodb:Scan",
    ]
    resources = [module.metadata_table.table_arn]
  }

  statement {
    sid    = "BucketWrite"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      module.site_bucket.bucket_arn,
      "${module.site_bucket.bucket_arn}/*",
    ]
  }

  statement {
    sid    = "CloudFrontInvalidation"
    effect = "Allow"
    actions = [
      "cloudfront:CreateInvalidation",
    ]
    resources = ["arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"]
  }
}

data "aws_iam_policy_document" "contact_lambda" {
  statement {
    sid    = "SendEmail"
    effect = "Allow"
    actions = [
      "ses:SendEmail",
    ]
    resources = [module.ses.email_identity_arn]
  }
}

module "acm" {
  source = "../../modules/acm"
  providers = {
    aws = aws.us_east_1
  }

  domain_name               = var.domain_name
  subject_alternative_names = [local.www_domain]
  wait_for_validation       = var.acm_wait_for_validation
  tags                      = local.common_tags
}

module "site_bucket" {
  source = "../../modules/s3-bucket"

  bucket_name          = "${local.name_prefix}-site"
  enable_cors          = true
  cors_allowed_origins = local.site_origins
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
  enable_point_in_time_recovery = var.enable_dynamodb_pitr
  tags                          = local.common_tags
}

module "cognito" {
  source = "../../modules/cognito"

  user_pool_name = "${local.name_prefix}-admins"
  admin_callback_urls = [
    "${local.site_origin}/admin/callback",
    "${local.www_origin}/admin/callback",
  ]
  admin_logout_urls = [
    "${local.site_origin}/admin",
    "${local.www_origin}/admin",
  ]
  tags = local.common_tags
}

module "ses" {
  source = "../../modules/ses-email"

  email_address = var.ses_email
  tags          = local.common_tags
}

module "lambda_publish" {
  source = "../../modules/lambda"

  function_name = "${local.name_prefix_safe}-publish"
  handler       = "handler.handler"
  source_dir    = "${path.module}/../../../lambda/publish"
  timeout       = 60
  memory_size   = 512

  environment_variables = merge({
    METADATA_TABLE_NAME = module.metadata_table.table_name
    SITE_BUCKET_NAME    = module.site_bucket.bucket_id
    PHOTOS_PREFIX       = "photos/"
    PHOTOS_CDN_URL      = "${local.site_origin}/photos"
    AWS_REGION_NAME     = var.aws_region
    }, var.cloudfront_distribution_id != "" ? {
    CLOUDFRONT_DISTRIBUTION_ID = var.cloudfront_distribution_id
  } : {})

  policy_json              = data.aws_iam_policy_document.publish_lambda.json
  permissions_boundary_arn = var.iam_permissions_boundary_arn
  tags                     = local.common_tags
}

module "lambda_contact" {
  source = "../../modules/lambda"

  function_name = "${local.name_prefix_safe}-contact"
  handler       = "handler.handler"
  source_dir    = "${path.module}/../../../lambda/contact"
  timeout       = 10
  memory_size   = 128

  environment_variables = {
    SES_FROM_EMAIL               = var.ses_email
    SES_TO_EMAIL                 = var.ses_email
    AWS_REGION_NAME              = var.aws_region
    ALLOWED_ORIGINS              = join(",", local.site_origins)
    RECAPTCHA_SECRET_KEY         = var.recaptcha_secret_key
    RECAPTCHA_EXPECTED_HOSTNAMES = join(",", [var.domain_name, local.www_domain])
    RECAPTCHA_EXPECTED_ACTION    = "contact"
    RECAPTCHA_MIN_SCORE          = tostring(var.recaptcha_min_score)
  }

  policy_json              = data.aws_iam_policy_document.contact_lambda.json
  permissions_boundary_arn = var.iam_permissions_boundary_arn
  tags                     = local.common_tags
}

module "api" {
  source = "../../modules/api"

  api_name                       = "${local.name_prefix}-api"
  enable_custom_domain           = false
  cors_allow_origins             = local.site_origins
  cognito_user_pool_id           = module.cognito.user_pool_id
  cognito_client_id              = module.cognito.admin_client_id
  publish_lambda_invoke_arn      = module.lambda_publish.invoke_arn
  publish_lambda_function_name   = module.lambda_publish.function_name
  contact_lambda_invoke_arn      = module.lambda_contact.invoke_arn
  contact_lambda_function_name   = module.lambda_contact.function_name
  enable_contact_route           = true
  contact_throttling_burst_limit = 10
  contact_throttling_rate_limit  = 5
  tags                           = local.common_tags
}

module "cloudfront" {
  source = "../../modules/cloudfront-app"

  distribution_name   = "${local.name_prefix}-app"
  aliases             = local.cloudfront_aliases
  acm_certificate_arn = local.use_custom_domain ? module.acm.certificate_arn : ""
  api_origin_domain   = replace(module.api.api_endpoint, "https://", "")

  site_bucket = {
    id                       = module.site_bucket.bucket_id
    arn                      = module.site_bucket.bucket_arn
    regional_domain_name     = module.site_bucket.bucket_regional_domain_name
    origin_access_control_id = module.site_bucket.origin_access_control_id
  }

  tags = local.common_tags

  depends_on = [module.api]
}

resource "aws_budgets_budget" "monthly_cost" {
  name         = "${local.name_prefix}-monthly-cost"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 10 # ~$5
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.admin_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 40 # ~$20
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.admin_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100 # $50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.admin_email]
  }
}
