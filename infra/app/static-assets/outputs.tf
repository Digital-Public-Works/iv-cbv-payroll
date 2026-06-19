output "bucket_name" {
  value = aws_s3_bucket.static_assets.bucket
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.static_assets.domain_name
}

output "static_assets_url" {
  value = "https://static.verifymyincome.org"
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.static_assets.id
}

output "access_policy_arn" {
  value = aws_iam_policy.static_assets_access.arn
}
