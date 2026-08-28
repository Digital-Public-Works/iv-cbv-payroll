# AWS Federation for GitHub Actions

This module sets up a way for GitHub Actions to access AWS resources using short-lived credentials without requiring long-lived access keys and without requiring separate AWS identities that need to be managed. It does that by doing the following:

1. Set up GitHub as an OpenID Connect Provider in the AWS account
2. Create an IAM role that GitHub actions will assume
3. Attach three least-privilege IAM policies to that role:
   - `<role>-infra-services` — coarse `<service>:*` for the services this project uses
   - `<role>-iam-scoped` — IAM read everywhere; role/policy lifecycle and `PassRole` confined to the resources named "app-*"
   - `<role>-guardrails` — explicit `Deny` protecting the CI role itself, the OIDC provider, the Terraform state backend, and customer data in RDS
