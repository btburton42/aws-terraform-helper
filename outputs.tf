output "bucket_name" {
  description = "Name of the created S3 bucket"
  value       = aws_s3_bucket.obsidian.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.obsidian.arn
}

output "bucket_regional_domain" {
  description = "Regional domain for S3 endpoint"
  value       = aws_s3_bucket.obsidian.bucket_regional_domain_name
}

output "iam_user_arn" {
  description = "ARN of the IAM user"
  value       = aws_iam_user.obsidian.arn
}

output "iam_user_name" {
  description = "Name of the IAM user"
  value       = aws_iam_user.obsidian.name
}

output "access_key_id" {
  description = "Access Key ID for Obsidian (STORE SECURELY)"
  value       = aws_iam_access_key.obsidian.id
}

output "secret_access_key" {
  description = "Secret Access Key for Obsidian (STORE IN PASSWORD MANAGER)"
  value       = aws_iam_access_key.obsidian.secret
  sensitive   = true
}

output "s3_endpoint" {
  description = "S3 endpoint URL for Obsidian configuration"
  value       = "https://s3.${var.aws_region}.amazonaws.com"
}

output "obsidian_config_file" {
  description = "Path to local configuration file"
  value       = local_file.obsidian_config.filename
}

output "seed_command" {
  description = "Command to seed vault contents"
  value       = <<-EOT
    
    # Configure AWS CLI profile
    aws configure --profile ${var.iam_user_name}
    # Access Key ID: ${aws_iam_access_key.obsidian.id}
    # Secret Access Key: (see secret_access_key output)
    
    # Seed your vault (replace ~/Documents/Obsidian with your path)
    aws s3 sync ~/Documents/Obsidian s3://${aws_s3_bucket.obsidian.id}/${var.vault_path}/ \
        --profile ${var.iam_user_name} \
        --storage-class STANDARD \
        --sse AES256
    
    # Or use the helper script:
    ./scripts/seed-vault.sh s3://${aws_s3_bucket.obsidian.id}/${var.vault_path} \
        ~/Documents/Obsidian \
        ${aws_iam_access_key.obsidian.id}
    EOT
}
