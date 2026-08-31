# guardrails — explicit deny the github runner from permissions
# that would be used in account takeover, data exfiltration, destructive actions, and OIDC backdoor

resource "aws_iam_role_policy_attachment" "guardrails" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.guardrails.arn
}

resource "aws_iam_policy" "guardrails" {
  name        = "${var.github_actions_role_name}-guardrails"
  description = "Explicit denies protecting the CI role, OIDC provider, TF state backend, and customer data in RDS."
  policy      = data.aws_iam_policy_document.guardrails.json
}

# basic protections against account takeover
data "aws_iam_policy_document" "guardrails" {
  statement {
    sid    = "DenySelfModification"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:DeleteRole",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:DeletePolicy",
    ]
    resources = [
      "arn:aws:iam::${var.aws_account_id}:role/${var.github_actions_role_name}",
      "arn:aws:iam::${var.aws_account_id}:policy/${var.github_actions_role_name}-*",
    ]
  }

  # basic protections against destructive actions on the terraform state backend
  # (state bucket, lock table, and its encryption key)
  statement {
    sid    = "DenyStateBackendDestruction"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketVersioning",
      "dynamodb:DeleteTable",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
    ]
    resources = [
      "arn:aws:s3:::${var.tf_state_bucket_name}",
      local.tf_locks_table_arn,
      var.tf_backend_kms_key_arn,
    ]
  }

  # basic protections against data exfiltration and destructive actions on the database
  statement {
    sid    = "DenyRdsWrites"
    effect = "Deny"
    actions = [
      "rds:Create*",
      "rds:Copy*",
      "rds:Modify*",
      "rds:Restore*",
      "rds:Start*",
      "rds:Delete*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyProjectKmsKeyPolicyTampering"
    effect = "Deny"
    actions = [
      "kms:PutKeyPolicy",
      "kms:CreateGrant",
      "kms:RetireGrant",
      "kms:RevokeGrant",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/project"
      values   = [var.project_tag]
    }
  }

  statement {
    sid       = "DenyDbMasterSecretRead"
    effect    = "Deny"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.db_managed_secret_arn]
  }

  # basic protections from backdoors created by tampering with OIDC configuration
  statement {
    sid    = "DenyOidcProviderTampering"
    effect = "Deny"
    actions = [
      "iam:CreateOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
    ]
    resources = ["*"]
  }
}
