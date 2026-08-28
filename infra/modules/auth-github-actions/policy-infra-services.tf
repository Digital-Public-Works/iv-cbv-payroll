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

#trivy:ignore:aws-0345 Coarse s3:* is intentional; state bucket destruction is denied in the guardrails policy.
data "aws_iam_policy_document" "infra_services" {
  #checkov:skip=CKV_AWS_111:Coarse service:* is intentional; escalation blocked by guardrails policy
  #checkov:skip=CKV_AWS_356:Coarse service:* on * is intentional; see guardrails policy
  statement {
    sid       = "ManageInfraServices"
    effect    = "Allow"
    actions   = var.infra_service_actions
    resources = ["*"]
  }
}
