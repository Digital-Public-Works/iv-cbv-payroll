# WORM archive for static-analysis scan reports (Brakeman today; other scanners
# can share the bucket under their own key prefix).
#
# GitHub Actions artifacts are capped at 90 days on public repos, which is below
# any plausible AU-11 audit-record retention window, so retention and immutability
# live here on the bucket instead: versioning + Object Lock + a lifecycle policy.
#
# Object Lock must be enabled at bucket creation -- it cannot be added to this
# bucket later without recreating it. Set var.retention_days deliberately before
# the first apply.

locals {
  bucket_name = "dpw-${module.project_config.project_name}-security-scan-reports"

  tags = merge(module.project_config.default_tags, {
    application      = module.project_config.project_name
    application_role = "security-scan-reports"
    description      = "Immutable archive of static-analysis scan reports (AU-11)"
  })
}

terraform {
  required_version = "~>1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.35.0, < 6.0.0"
    }
  }

  backend "s3" {
    encrypt = "true"
  }
}

provider "aws" {
  region = module.project_config.default_region

  default_tags {
    tags = local.tags
  }
}

module "project_config" {
  source = "../../project-config"
}

resource "aws_s3_bucket" "reports" {
  # checkov:skip=CKV_AWS_18:Access logging tracked separately; object-level audit is via CloudTrail
  # checkov:skip=CKV_AWS_144:Cross-region replication not required for scan reports
  # checkov:skip=CKV_AWS_145:AES256 encryption is sufficient; KMS not required
  # checkov:skip=CKV2_AWS_62:Event notifications not needed for scan reports
  bucket = local.bucket_name

  # Cannot be turned on after creation. Recreating this bucket would destroy the
  # audit record, so this must be correct on the first apply.
  object_lock_enabled = true
}

resource "aws_s3_bucket_public_access_block" "reports" {
  bucket = aws_s3_bucket.reports.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Object Lock requires versioning, and versioning is what makes an overwrite of an
# existing key non-destructive.
resource "aws_s3_bucket_versioning" "reports" {
  bucket = aws_s3_bucket.reports.id

  versioning_configuration {
    status = "Enabled"
  }
}

#trivy:ignore:aws-0132 AES256 encryption is sufficient; KMS not required (see CKV_AWS_145 skip above)
resource "aws_s3_bucket_server_side_encryption_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Default retention applied to every uploaded object version. In COMPLIANCE mode
# no principal -- including the account root -- can delete or overwrite a version
# before its retention expires, which is the point: the GitHub Actions role that
# writes these reports currently has account-admin permissions (see PF-795).
resource "aws_s3_bucket_object_lock_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.reports]
}

# Retention is enforced by lifecycle rules, never by manual deletion, so the schedule
# is self-documenting and an assessor can read it straight off the bucket:
#
#   0 - hot_days           S3 Standard      AU-11 "online" window
#   hot_days - expiration  archive class    long-term retention
#   expiration_days        deleted
#
# A transition does not conflict with Object Lock -- the lock prevents deletion and
# overwrite, not storage-class changes. Expiration does interact: a locked version
# survives the rule until its retention expires, which is why expiration_days must
# be >= object_lock_retention_days (asserted below).
resource "aws_s3_bucket_lifecycle_configuration" "reports" {
  bucket = aws_s3_bucket.reports.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "archive-then-expire"
    status = "Enabled"
    filter {}

    transition {
      days          = var.hot_days
      storage_class = var.archive_storage_class
    }

    expiration {
      days = var.expiration_days
    }

    # A re-run of the same commit writes the same key; the superseded version is
    # still an audit record and follows the same schedule.
    noncurrent_version_transition {
      noncurrent_days = var.hot_days
      storage_class   = var.archive_storage_class
    }

    noncurrent_version_expiration {
      noncurrent_days = var.expiration_days
    }
  }

  # Cross-variable rules cannot live in a variable block on Terraform 1.8, and a
  # `check` block only emits a warning. A precondition fails the plan outright,
  # which is what this invariant warrants: expiring before the lock releases is a
  # silent no-op that would look like retention is working when it is not.
  lifecycle {
    precondition {
      condition     = var.expiration_days >= var.object_lock_retention_days
      error_message = "expiration_days (${var.expiration_days}) is shorter than object_lock_retention_days (${var.object_lock_retention_days}); locked versions would survive the lifecycle rule."
    }
  }

  depends_on = [aws_s3_bucket_versioning.reports]
}

# TLS-only.
resource "aws_s3_bucket_policy" "reports" {
  bucket     = aws_s3_bucket.reports.id
  policy     = data.aws_iam_policy_document.reports_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.reports]
}

data "aws_iam_policy_document" "reports_bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = [
      aws_s3_bucket.reports.arn,
      "${aws_s3_bucket.reports.arn}/*",
    ]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
