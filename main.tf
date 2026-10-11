provider "aws" {
  region = var.aws_region
}

locals {
  bucket_name = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"
}

# Generate random suffix for unique bucket name
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# S3 Bucket with security hardening
resource "aws_s3_bucket" "obsidian" {
  bucket = local.bucket_name

  tags = {
    Name        = "Obsidian Sync"
    Description = "Private vault sync for Obsidian"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_versioning" "obsidian" {
  bucket = aws_s3_bucket.obsidian.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "obsidian" {
  bucket = aws_s3_bucket.obsidian.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "obsidian" {
  bucket = aws_s3_bucket.obsidian.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CORS Configuration for Obsidian mobile/desktop apps
resource "aws_s3_bucket_cors_configuration" "obsidian" {
  bucket = aws_s3_bucket.obsidian.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag", "x-amz-server-side-encryption"]
    max_age_seconds = 3000
  }
}

# Lifecycle policy for cost control
resource "aws_s3_bucket_lifecycle_configuration" "obsidian" {
  count  = var.noncurrent_version_expiration_days > 0 ? 1 : 0
  bucket = aws_s3_bucket.obsidian.id

  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

# IAM User for Obsidian with least privilege
resource "aws_iam_user" "obsidian" {
  name          = var.iam_user_name
  force_destroy = true

  tags = {
    Description = "Dedicated user for Obsidian S3 sync"
  }
}

resource "aws_iam_access_key" "obsidian" {
  user = aws_iam_user.obsidian.name
}

resource "aws_iam_user_policy" "obsidian" {
  name = "ObsidianSyncLimitedAccess"
  user = aws_iam_user.obsidian.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:ListBucketVersions",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.obsidian.arn
      },
      {
        Sid    = "ObjectOperations"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${aws_s3_bucket.obsidian.arn}/*"
      }
    ]
  })
}

# Defense in depth: Force HTTPS via bucket policy
resource "aws_s3_bucket_policy" "obsidian" {
  bucket = aws_s3_bucket.obsidian.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.obsidian.arn,
          "${aws_s3_bucket.obsidian.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# Local file with configuration for easy reference
resource "local_file" "obsidian_config" {
  content = <<EOF
========================================
OBSIDIAN REMOTELY SAVE CONFIGURATION
========================================

Service Type:        S3
Endpoint:            https://s3.${var.aws_region}.amazonaws.com
Region:              ${var.aws_region}
Access Key ID:       ${aws_iam_access_key.obsidian.id}
Secret Access Key:   ${aws_iam_access_key.obsidian.secret}
Bucket Name:         ${aws_s3_bucket.obsidian.id}
Path Prefix:         ${var.vault_path}/
Force Path Style:    false
Disable S3 URI Encoding: false

========================================
SECURITY NOTES
========================================
- Store this file securely (chmod 600)
- Secret Access Key shown only once during creation
- If lost, run: terraform apply -replace=aws_iam_access_key.obsidian
- Rotate keys regularly using: ./scripts/rotate-keys.sh

========================================
QUICK COMMANDS
========================================

# Configure AWS CLI profile:
aws configure --profile ${var.iam_user_name}

# Sync your vault:
aws s3 sync ~/Documents/Obsidian s3://${aws_s3_bucket.obsidian.id}/${var.vault_path}/ \
    --profile ${var.iam_user_name} \
    --exclude ".obsidian/*" \
    --delete

# List bucket contents:
aws s3 ls s3://${aws_s3_bucket.obsidian.id}/ --recursive --profile ${var.iam_user_name}

========================================
EOF

  filename        = "obsidian-config-${local.bucket_name}.txt"
  file_permission = "0600"
}
