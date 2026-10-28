output "content_hash" {
  description = "Hash of the synced file list; a change triggers a new sync and CloudFront invalidation."
  value       = local.content_hash
}

output "file_count" {
  description = "Number of files synced from source_dir."
  value       = length(local.files)
}

output "script_path" {
  description = "Absolute path of sync.sh, the script that publishes source_dir and invalidates CloudFront."
  value       = abspath("${path.module}/sync.sh")
}
