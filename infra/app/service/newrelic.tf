# NewRelic IAM role is created in standard environments (demo, prod) and shared across all environments.
# Other environments (a11y, preview) reference it via data source.
resource "aws_iam_role" "newrelic_metrics" {
  count = (var.environment_name == "demo" || var.environment_name == "prod") && !local.is_temporary ? 1 : 0
  # checkov:skip=CKV_AWS_61:This policy principal needs to be broad to allow for monitoring all services.

  name = "newrelic-metrics-collector"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          AWS = "754728514883" # NewRelic's AWS Account ID
        }
        Condition = {
          StringEquals = {
            "sts:ExternalId" = local.environment_config.newrelic_config.account_id
          }
        }
      }
    ]
  })

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Reference the shared NewRelic IAM role created in standard environments
data "aws_iam_role" "newrelic_metrics" {
  count = var.environment_name != "demo" && var.environment_name != "prod" && !local.is_temporary ? 1 : 0
  name  = "newrelic-metrics-collector"
}

resource "aws_iam_role_policy_attachment" "newrelic_metrics" {
  count      = (var.environment_name == "demo" || var.environment_name == "prod") && !local.is_temporary ? 1 : 0
  role       = aws_iam_role.newrelic_metrics[0].id
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
