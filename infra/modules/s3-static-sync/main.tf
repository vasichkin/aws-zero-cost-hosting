variable "bucket_id" {
  description = "Target S3 bucket ID."
  type        = string
}

variable "source_dir" {
  description = "Local directory synced to the bucket root (objects missing locally are deleted from the bucket)."
  type        = string
}

variable "distribution_id" {
  description = "CloudFront distribution ID to invalidate after a sync. Empty skips the invalidation."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region used by the AWS CLI."
  type        = string
}

variable "cache_control" {
  description = "Cache-Control header for uploaded objects."
  type        = string
  default     = "public, max-age=3600"
}

# Objects are uploaded by the AWS CLI, so they never enter the tofu state; only this hash does.
# Dotfiles at any depth (.DS_Store, .gitkeep, ...) are ignored here and excluded from the sync below.
locals {
  files = [
    for path in sort(fileset(var.source_dir, "**/*")) : path
    if !anytrue([for segment in split("/", path) : startswith(segment, ".")])
  ]

  content_hash = sha1(join(",", [for path in local.files : "${path}:${filemd5("${var.source_dir}/${path}")}"]))
}

# Requires the AWS CLI on the machine running tofu, using the same credentials.
# sync.sh prints every uploaded/deleted file and a final "Sync status" line into the apply log.
resource "terraform_data" "sync" {
  triggers_replace = [local.content_hash, var.bucket_id, var.distribution_id, var.cache_control]

  provisioner "local-exec" {
    command = "'${abspath("${path.module}/sync.sh")}'"

    environment = {
      SOURCE_DIR      = var.source_dir
      BUCKET          = var.bucket_id
      CACHE_CONTROL   = var.cache_control
      DISTRIBUTION_ID = var.distribution_id
      AWS_REGION      = var.region
    }
  }
}

# Migration from the previous aws_s3_object implementation: forget the old per-file resources
# without deleting the objects. Safe to delete this block once every environment has applied it.
removed {
  from = aws_s3_object.this

  lifecycle {
    destroy = false
  }
}
