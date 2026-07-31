# Set up GitHub's OpenID Connect provider in AWS account
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# Create IAM role for GitHub Actions
resource "aws_iam_role" "github_actions" {
  name               = var.github_actions_role_name
  description        = "Service role required for Github Action to deploy application resources into the account."
  assume_role_policy = data.aws_iam_policy_document.github_assume_role.json
}

# Attach access policies to GitHub Actions role
resource "aws_iam_role_policy_attachment" "github_actions" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.github_actions.arn
}

resource "aws_iam_policy" "github_actions" {
  name        = "${var.github_actions_role_name}-manage-infra"
  description = "Allow ${var.github_actions_role_name} to manage AWS infrastructure resources"
  policy      = data.aws_iam_policy_document.github_actions.json
}

# KNOWN RISK, NOT ROUTINE: this policy grants iam:* on resources=["*"], which lets this role
# grant itself any permission (incl. full admin) — it is not meaningfully bounded by the "*.serviceX:*" action list.
# The trust policy (see github_assume_role below) also allows any ref in this repo, not just protected branches.
# Effectively: any GitHub Actions run in this repo can act as AWS account admin.
# Scoping tracked in PF-795 (Infra defect: GitHub Actions deploy has root iam role).
#trivy:ignore:aws-0345
data "aws_iam_policy_document" "github_actions" {
  statement {
    sid       = "ManageInfra"
    effect    = "Allow"
    actions   = var.allowed_actions
    resources = ["*"]
  }
}

# Set up assume role policy for GitHub Actions to allow GitHub actions
# running from the specified repository and branches/git refs to assume
# the role
data "aws_iam_policy_document" "github_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:*"]
    }
  }
}
