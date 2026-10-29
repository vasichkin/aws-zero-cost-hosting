terraform {
  required_version = ">= 1.10.0" # use_lockfile (S3-native state locking)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Bucket/region supplied via backend.hcl at init (see backend.hcl.example).
  # Locking uses a .tflock object next to the state file in the same bucket.
  backend "s3" {
    key          = "prod/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
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
  # tofu always lets terraform.tfvars beat TF_VAR_<same name>, so the environment uses its own variable and wins here.
  recaptcha_secret_key = var.recaptcha_secret_key_env != "" ? var.recaptcha_secret_key_env : var.recaptcha_secret_key
  www_domain           = "www.${var.domain_name}"
  site_origin          = "https://${var.domain_name}"
  www_origin           = "https://${local.www_domain}"
  site_origins         = [local.site_origin, local.www_origin]
  use_custom_domain    = var.acm_wait_for_validation
  cloudfront_aliases   = local.use_custom_domain ? [var.domain_name, local.www_domain] : []
}

resource "terraform_data" "require_recaptcha_secret" {
  lifecycle {
    precondition {
      condition     = local.recaptcha_secret_key != ""
      error_message = "reCAPTCHA secret is not set. Export TF_VAR_recaptcha_secret_key_env or set recaptcha_secret_key in terraform.tfvars."
    }
  }
}

# Shared between CloudFront (sends it) and the Lambda (requires it): blocks direct hits on the execute-api URL.
resource "random_password" "origin_verify" {
  length  = 40
  special = false
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

  bucket_name = var.site_bucket_name
  # Site content is uploaded by aws s3 sync (not in state), so destroy must empty the bucket itself.
  force_destroy = true
  tags          = local.common_tags
}

module "website_sync" {
  source = "../../modules/s3-static-sync"

  bucket_id       = module.site_bucket.bucket_id
  source_dir      = "${path.module}/../../../website"
  distribution_id = module.cloudfront.distribution_id
  region          = var.aws_region
}

module "ses" {
  source = "../../modules/ses-email"

  email_address = var.ses_email
  tags          = local.common_tags
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
    RECAPTCHA_SECRET_KEY         = local.recaptcha_secret_key
    RECAPTCHA_EXPECTED_HOSTNAMES = join(",", [var.domain_name, local.www_domain])
    RECAPTCHA_EXPECTED_ACTION    = "contact"
    RECAPTCHA_MIN_SCORE          = tostring(var.recaptcha_min_score)
    ORIGIN_VERIFY_SECRET         = random_password.origin_verify.result
  }

  policy_json              = data.aws_iam_policy_document.contact_lambda.json
  permissions_boundary_arn = var.iam_permissions_boundary_arn
  tags                     = local.common_tags
}

module "api" {
  source = "../../modules/api"

  api_name                       = "${local.name_prefix}-api"
  cors_allow_origins             = local.site_origins
  contact_lambda_invoke_arn      = module.lambda_contact.invoke_arn
  contact_lambda_function_name   = module.lambda_contact.function_name
  enable_contact_route           = true
  contact_throttling_burst_limit = 1
  contact_throttling_rate_limit  = 1 / 60 # 1 request per minute, shared by all visitors
  tags                           = local.common_tags
}

module "cloudfront" {
  source = "../../modules/cloudfront-app"

  distribution_name   = "${local.name_prefix}-app"
  aliases             = local.cloudfront_aliases
  acm_certificate_arn = local.use_custom_domain ? module.acm.certificate_arn : ""
  api_origin_domain   = replace(module.api.api_endpoint, "https://", "")

  api_origin_verify_secret = random_password.origin_verify.result

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
