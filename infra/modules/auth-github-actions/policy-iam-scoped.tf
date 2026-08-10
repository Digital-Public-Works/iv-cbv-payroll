# iam-scoped — grants limited-in-scope permissions to the github action runner
# for managing IAM policies and roles.

resource "aws_iam_role_policy_attachment" "iam_scoped" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.iam_scoped.arn
}

resource "aws_iam_policy" "iam_scoped" {
  name        = "${var.github_actions_role_name}-iam-scoped"
  description = "Allow ${var.github_actions_role_name} to manage only the app's service IAM roles, and pass them only to the services that use them."
  policy      = data.aws_iam_policy_document.iam_scoped.json
}

data "aws_iam_policy_document" "iam_scoped" {
  # including resources it doesn't manage (data-source lookups, drift-check reads
  # of the CI role / OIDC provider). Read-only, no mutation. The write statements
  # in this document are all scoped to app-*.
  #checkov:skip=CKV_AWS_356:IamReadOnly is read-only on *; write statements are scoped to app-*
  # allow runner to read IAM state during terraform plan and apply
  statement {
    sid       = "IamReadOnly"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  # allow runner to fully manage iam service roles related to the app
  statement {
    sid    = "ServiceRoleLifecycle"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = local.service_role_arns
  }

  # allow runner to fully manage iam policies related to the app
  statement {
    sid    = "ServicePolicyLifecycle"
    effect = "Allow"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = local.service_policy_arns
  }

  #  allow runner to hand the app's app-* roles to ECS/EventBridge/Scheduler/Step Functions
  statement {
    sid       = "PassServiceRolesToAwsServices"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = local.service_role_arns
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values = [
        "ecs-tasks.amazonaws.com",
        "events.amazonaws.com",
        "scheduler.amazonaws.com",
        "states.amazonaws.com",
      ]
    }
  }
}
