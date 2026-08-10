# infra-services — coarse <service>:* for the services the repo actually uses.
# RDS is read-only (see policy-guardrails.tf for the write denies).

resource "aws_iam_role_policy_attachment" "infra_services" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.infra_services.arn
}

resource "aws_iam_policy" "infra_services" {
  name        = "${var.github_actions_role_name}-infra-services"
  description = "Allow ${var.github_actions_role_name} to manage the AWS services this project uses."
  policy      = data.aws_iam_policy_document.infra_services.json
}

data "aws_iam_policy_document" "infra_services" {
  statement {
    sid       = "ManageInfraServices"
    effect    = "Allow"
    actions   = var.infra_service_actions
    resources = ["*"]
  }
}
