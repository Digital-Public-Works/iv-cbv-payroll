locals {
  # IAM roles/policies this role may manage.
  service_role_arns = [
    # App service resources are named "app-<env>-..." (e.g. app-demo-migrator)
    "arn:aws:iam::${var.aws_account_id}:role/app-*",
    # SES needs a service role to forward email observability events to New Relic
    "arn:aws:iam::${var.aws_account_id}:role/${var.ses_events_role_name}",
  ]
  service_policy_arns = ["arn:aws:iam::${var.aws_account_id}:policy/app-*"]

  tf_locks_table_arn = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.tf_state_bucket_name}-state-locks"

  # CI never needs to read any RDS-managed secret, so a broad deny here is safe.
  db_managed_secret_arn = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:rds!*"
}
