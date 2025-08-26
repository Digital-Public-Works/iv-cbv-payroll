resource "random_string" "s3_bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  sftp_bucket_full_name = "${var.storage_bucket_name_prefix}${data.aws_caller_identity.current.account_id}-${random_string.s3_bucket_suffix.result}"
}

module "storage" {
  source = "../modules/storage"
  name         = local.sftp_bucket_full_name
  is_temporary = true
}