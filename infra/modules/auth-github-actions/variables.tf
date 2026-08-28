variable "github_actions_role_name" {
  type        = string
  description = "The name to use for the IAM role GitHub actions will assume."
}

variable "github_repository" {
  type        = string
  description = "The GitHub repository in 'org/repo' format to provide access to AWS account resources."
}

variable "aws_account_id" {
  type        = string
  description = "The AWS account ID this role is being created in."
}

variable "aws_region" {
  type        = string
  description = "The AWS region resources live in (used to build ARNs)."
}

variable "tf_state_bucket_name" {
  type        = string
  description = "Name of the Terraform state S3 bucket, protected from destruction by the guardrails policy."
}

variable "tf_backend_kms_key_arn" {
  type        = string
  description = "ARN of the KMS key encrypting the Terraform state backend, protected from tampering by the guardrails policy."
}

variable "project_tag" {
  type        = string
  default     = "iv-cbv-payroll"
  description = "Value of the 'project' resource tag; used to scope the KMS key-policy guardrail to this project's keys."
}

variable "infra_service_actions" {
  type        = list(string)
  description = "Coarse per-service allow actions for the infra-services policy. RDS is intentionally read-only."
  default = [
    "acm:*",
    "backup:*",
    "cloudwatch:*",
    "dynamodb:*",
    "ec2:*",
    "ecr:*",
    "ecs:*",
    "elasticloadbalancing:*",
    "events:*",
    "kms:*",
    "lambda:*",
    "logs:*",
    "rds:Describe*",
    "rds:ListTagsForResource",
    "route53:*",
    "s3:*",
    "scheduler:*",
    "secretsmanager:*",
    "ses:*",
    "sns:*",
    "sqs:*",
    "ssm:*",
    "states:*",
  ]
}

variable "ses_events_role_name" {
  type        = string
  default     = "SESEventsToNewRelic"
  description = "IAM role needed for SES to send email observability events to New Relic"
}
