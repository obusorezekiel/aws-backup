output "bucket_name" {
  value = module.l2_backup_account.bucket_name
}

output "bucket_arn" {
  value = module.l2_backup_account.bucket_arn
}

output "kms_key_arn" {
  value = module.l2_backup_account.kms_key_arn
}

output "kms_key_id" {
  value = module.l2_backup_account.kms_key_id
} 