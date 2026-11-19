output "github_oidc_provider_arn" {
  value = aws_iam_openid_connect_provider.github.arn
}

output "region" {
  value = module.project_config.default_region
}

output "tf_locks_table_name" {
  value = module.backend.tf_locks_table_name
}

output "tf_state_bucket_name" {
  value = module.backend.tf_state_bucket_name
}
