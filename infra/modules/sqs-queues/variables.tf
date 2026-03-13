variable "environment_name" {
  type        = string
  description = "The environment name (e.g., demo, a11y, prod)"
}

variable "use_environment_suffix" {
  type        = bool
  default     = false
  description = "Whether to append environment name to queue names. Set to true for non-standard environments (a11y, preview) to avoid resource conflicts. Standard environments (demo, prod) keep original names for backward compatibility."
}

variable "queue_names" { type = set(string) }
variable "dlq_name" { type = string }
variable "visibility_timeout_seconds" { type = number }
variable "receive_wait_time_seconds" { type = number }
variable "message_retention_seconds" { type = number }
variable "max_receive_count" { type = number }
