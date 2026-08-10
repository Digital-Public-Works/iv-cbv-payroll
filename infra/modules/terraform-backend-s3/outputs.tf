output "tf_locks_table_name" {
  value = aws_dynamodb_table.terraform_lock.name
}

output "tf_log_bucket_name" {
  value = aws_s3_bucket.tf_log.bucket
}

output "tf_state_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "tf_backend_kms_key_arn" {
  value = aws_kms_key.tf_backend.arn
}
