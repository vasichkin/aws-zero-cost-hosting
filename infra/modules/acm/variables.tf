variable "wait_for_validation" {
  description = "Block until ACM DNS validation completes. Set false on first apply with external DNS."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the certificate."
  type        = map(string)
  default     = {}
}
