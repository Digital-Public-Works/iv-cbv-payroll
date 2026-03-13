locals {
  # Resource naming strategy:
  # - Standard environments (demo, prod): no suffix (backward compatible, no state migration)
  # - New environments (a11y, preview): with suffix (prevents resource name conflicts)
  #
  # This allows multiple environments to coexist without shared resource conflicts,
  # while maintaining backward compatibility for existing deployments.
  suffix         = var.use_environment_suffix ? "_${var.environment_name}" : ""
  resolved_names = [for n in var.queue_names : "${n}${local.suffix}"]
  dlq_resolved   = "${var.dlq_name}${local.suffix}"

  # Only protect DLQ for permanent environments (demo, prod).
  # Temporary/ephemeral environments (a11y, preview) can be destroyed cleanly.
  is_permanent_environment = var.environment_name == "demo" || var.environment_name == "prod"
}

resource "aws_sqs_queue" "dicit_queues" {
  for_each = toset(local.resolved_names)

  name                       = each.key
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  delay_seconds              = 0
  message_retention_seconds  = var.message_retention_seconds
  max_message_size           = 262144
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue" "dlq" {
  name                      = local.dlq_resolved
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true

  lifecycle {
    prevent_destroy = local.is_permanent_environment
  }

  redrive_allow_policy = jsonencode({ redrivePermission = "allowAll" })
}
