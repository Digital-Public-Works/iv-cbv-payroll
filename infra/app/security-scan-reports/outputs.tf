output "bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.reports.arn
}

output "report_writer_role_arn" {
  description = "Role GitHub Actions assumes to publish reports (.github/workflows/brakeman-analysis.yml)."
  value       = aws_iam_role.report_writer.arn
}
