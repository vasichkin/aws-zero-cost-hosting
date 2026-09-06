variable "bucket_id" {
  description = "Target S3 bucket ID."
  type        = string
}

variable "source_dir" {
  description = "Local directory whose files are uploaded to the bucket."
  type        = string
}

variable "prefix" {
  description = "Optional S3 key prefix (empty = bucket root)."
  type        = string
  default     = ""
}

variable "cache_control" {
  description = "Cache-Control header for uploaded objects."
  type        = string
  default     = "public, max-age=3600"
}

variable "tags" {
  description = "Tags applied to S3 objects."
  type        = map(string)
  default     = {}
}

locals {
  mime_types = {
    css  = "text/css; charset=utf-8"
    gif  = "image/gif"
    htm  = "text/html; charset=utf-8"
    html = "text/html; charset=utf-8"
    ico  = "image/x-icon"
    jpeg = "image/jpeg"
    jpg  = "image/jpeg"
    js   = "application/javascript; charset=utf-8"
    json = "application/json; charset=utf-8"
    png  = "image/png"
    svg  = "image/svg+xml"
    txt  = "text/plain; charset=utf-8"
    webp = "image/webp"
    xml  = "application/xml; charset=utf-8"
  }

  files = {
    for path in fileset(var.source_dir, "**/*") : path => path
    if !endswith(path, ".gitkeep") && !startswith(path, ".")
  }
}

resource "aws_s3_object" "this" {
  for_each = local.files

  bucket        = var.bucket_id
  key           = var.prefix != "" ? "${var.prefix}/${each.key}" : each.key
  source        = "${var.source_dir}/${each.key}"
  etag          = filemd5("${var.source_dir}/${each.key}")
  content_type  = try(local.mime_types[regex("\\.([^.]+)$", each.key)[0]], "application/octet-stream")
  cache_control = var.cache_control

  tags = merge(var.tags, {
    Name = each.key
  })
}
