output "bucket_name" {
  value = aws_s3_bucket.layer2.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.layer2.arn
}

output "kms_key_arn" {
  value = aws_kms_key.layer2.arn
}

output "kms_key_id" {
  value = aws_kms_key.layer2.key_id
} 