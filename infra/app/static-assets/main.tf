data "aws_caller_identity" "current" {}

data "aws_route53_zone" "zone" {
  name         = "verifymyincome.org"
  private_zone = false
}

data "aws_acm_certificate" "wildcard" {
  domain   = "*.verifymyincome.org"
  statuses = ["ISSUED"]
}

locals {
  bucket_name = "dpw-${module.project_config.project_name}-static-assets"

  tags = merge(module.project_config.default_tags, {
    application      = module.project_config.project_name
    application_role = "static-assets"
    description      = "S3 bucket and CloudFront distribution for static assets"
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

# KMS key for bucket encryption
resource "aws_kms_key" "static_assets" {
  description             = "KMS key for static assets bucket"
  deletion_window_in_days = 10
  enable_key_rotation     = true
}

# KMS key policy: account root admin + CloudFront decrypt access
# Set as a separate resource so it can reference the CloudFront distribution ARN
resource "aws_kms_key_policy" "static_assets" {
  key_id = aws_kms_key.static_assets.id
  policy = data.aws_iam_policy_document.static_assets_kms.json
}

data "aws_iam_policy_document" "static_assets_kms" {
  statement {
    sid     = "EnableIAMUserPermissions"
    effect  = "Allow"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    resources = ["*"]
  }

  statement {
    sid     = "AllowCloudFrontDecrypt"
    effect  = "Allow"
    actions = ["kms:Decrypt"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.static_assets.arn]
    }
  }
}

# S3 bucket
resource "aws_s3_bucket" "static_assets" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.static_assets.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy: TLS-only + CloudFront OAC read access
# Separate resource (not inline on bucket) so it can depend on the distribution ARN
resource "aws_s3_bucket_policy" "static_assets" {
  bucket     = aws_s3_bucket.static_assets.id
  policy     = data.aws_iam_policy_document.static_assets_bucket.json
  depends_on = [aws_s3_bucket_public_access_block.static_assets]
}

data "aws_iam_policy_document" "static_assets_bucket" {
  statement {
    sid     = "AllowCloudFrontServicePrincipal"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.static_assets.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.static_assets.arn]
    }
  }

  statement {
    sid       = "DenyNonTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.static_assets.arn, "${aws_s3_bucket.static_assets.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# CloudFront Origin Access Control
resource "aws_cloudfront_origin_access_control" "static_assets" {
  name                              = local.bucket_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "static_assets" {
  enabled     = true
  comment     = "${module.project_config.project_name} static assets"
  price_class = "PriceClass_100"
  aliases     = ["static.verifymyincome.org"]

  origin {
    domain_name              = aws_s3_bucket.static_assets.bucket_regional_domain_name
    origin_id                = local.bucket_name
    origin_access_control_id = aws_cloudfront_origin_access_control.static_assets.id
  }

  default_cache_behavior {
    target_origin_id       = local.bucket_name
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.wildcard.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_route53_record" "static_assets" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "static.verifymyincome.org"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.static_assets.domain_name
    zone_id                = aws_cloudfront_distribution.static_assets.hosted_zone_id
    evaluate_target_health = false
  }
}

# IAM policy to allow the app to upload assets to the bucket
resource "aws_iam_policy" "static_assets_access" {
  name        = "${local.bucket_name}-access"
  description = "Allows read/write access to the static assets bucket"
  policy      = data.aws_iam_policy_document.static_assets_access.json
}

data "aws_iam_policy_document" "static_assets_access" {
  statement {
    actions = [
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
    ]
    effect    = "Allow"
    resources = [aws_s3_bucket.static_assets.arn, "${aws_s3_bucket.static_assets.arn}/*"]
  }

  statement {
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    effect    = "Allow"
    resources = [aws_kms_key.static_assets.arn]
  }
}
