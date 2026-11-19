# Log-archive account

A dedicated AWS account for **immutable audit evidence**. Its ID is `log_archive_account_id` in
`infra/project-config`. It currently holds the static-analysis scan reports
(`infra/app/security-scan-reports`). It is designed so other audit records can be added later as
separate buckets.

## Why a separate account

The deciding factor is **who can delete the evidence**.

- **No workload runs in this account and it has no deploy role.** A compromised CI pipeline or
  application credential cannot reach the archive.
- **An organization Service Control Policy (SCP) protects it.** The SCP prevents anyone in the
  account, administrators and the root user included, from weakening or deleting archived data.
  The only exception is a controlled break-glass role.
- **Each writer can only add objects.** Every source gets its own narrowly scoped role or service
  principal.

This follows AWS's reference multi-account layout, where a Security OU holds a Log Archive account.
It supports these controls:

| Control | How |
|---|---|
| NIST 800-53 AU-9 (protection of audit information) | Separate account, SCP, write-only writers |
| AU-9(4) (access by a subset of privileged users) | Protection changes require the break-glass role |
| AU-11 (audit record retention) | Object Lock default retention plus lifecycle rules |

## Setup

Run every step with the break-glass profile. The first applies configure settings the SCP
protects. Both root modules pin `allowed_account_ids` to this account, so a wrong profile fails
instead of applying elsewhere.

1. Bootstrap the state backend, the GitHub OIDC provider and the account-wide S3 public access
   block:

   ```
   make infra-set-up-log-archive-account
   ```

2. Create the scan-report bucket and its write-only CI role:

   ```
   make infra-update-app-security-scan-reports APP_NAME=app
   ```

3. Attach the archive SCP from the management account.

4. Verify the setup:
   - An ordinary admin cannot change the bucket's versioning or lock settings.
   - The break-glass role can.
   - The next Brakeman run on `main` publishes a report. After it does, remove the two
     `continue-on-error` lines in `.github/workflows/brakeman-analysis.yml`.

Later changes to `infra/log-archive` use `make infra-update-log-archive-account`.

## Adding another archived source

Everything at the account level is independent of the data it stores. To add a source:

- **Create a bucket that follows the existing archive bucket naming convention**, which the SCP
  depends on to cover it. Enable Object Lock
  **at creation** (it can't be added later), plus versioning, default retention, lifecycle rules
  and TLS-only access. `infra/app/security-scan-reports/main.tf` is the reference. Extract it into
  a reusable module when there's a second bucket.
- **Grant only the writer the source needs:**
  - AWS services delivering from other accounts get a bucket-policy grant to their service
    principal, scoped with `aws:SourceAccount` / `aws:SourceArn`.
  - CI or application writers get a role limited to `s3:PutObject` on their own key prefix.
- **Apply the change with the break-glass profile.**
