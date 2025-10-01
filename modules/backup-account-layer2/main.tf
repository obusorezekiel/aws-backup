data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_key" {
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

  dynamic "statement" {
    for_each = length(var.admin_role_arns) > 0 ? [1] : []
    content {
      sid    = "AllowKeyAdmins"
      effect = "Allow"
      actions = [
        "kms:Create*","kms:Describe*","kms:Enable*","kms:List*","kms:Put*","kms:Update*",
        "kms:Revoke*","kms:Disable*","kms:Get*","kms:Delete*","kms:TagResource",
        "kms:UntagResource","kms:ScheduleKeyDeletion","kms:CancelKeyDeletion"
      ]
      principals {
        type        = "AWS"
        identifiers = var.admin_role_arns
      }
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = toset(var.s3_allowed_writer_role_arns)
    content {
      sid    = "AllowSourceCodeBuildUseOfKey"
      effect = "Allow"
      actions = ["kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      principals {
        type        = "AWS"
        identifiers = [statement.value]
      }
      resources = ["*"]
    }
  }
}

resource "aws_kms_key" "layer2" {
  description         = "Layer 2 CMK for pg_dump backups"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms_key.json
  multi_region        = var.kms_multi_region
  tags                = var.tags
}

resource "aws_kms_alias" "layer2" {
  name          = var.kms_alias
  target_key_id = aws_kms_key.layer2.key_id
}

resource "aws_s3_bucket" "layer2" {
  bucket = var.bucket_name
  tags   = var.tags
}

resource "aws_s3_bucket_public_access_block" "pab" {
  bucket                  = aws_s3_bucket.layer2.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "enc" {
  bucket = aws_s3_bucket.layer2.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.layer2.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lc" {
  bucket = aws_s3_bucket.layer2.id
  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }
    transition {
      days          = var.transition_to_deep_days
      storage_class = "DEEP_ARCHIVE"
    }
    expiration {
      days = var.expire_after_days
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "RequireKmsSse"
    effect  = "Deny"
    actions = ["s3:PutObject"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.layer2.arn}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }

  statement {
    sid     = "RequireSpecificKmsKey"
    effect  = "Deny"
    actions = ["s3:PutObject"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    resources = ["${aws_s3_bucket.layer2.arn}/*"]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [aws_kms_key.layer2.arn, aws_kms_key.layer2.key_id]
    }
  }

  statement {
    sid    = "AllowSourceCodeBuildPut"
    effect = "Allow"
    actions = ["s3:PutObject","s3:PutObjectAcl","s3:AbortMultipartUpload"]
    principals {
      type        = "AWS"
      identifiers = var.s3_allowed_writer_role_arns
    }
    resources = ["${aws_s3_bucket.layer2.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.layer2.id
  policy = data.aws_iam_policy_document.bucket.json
} 