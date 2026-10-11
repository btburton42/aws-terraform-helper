variable "aws_region" {
  description = "AWS region for S3 bucket"
  type        = string
  default     = "us-east-1"
}

variable "bucket_prefix" {
  description = "Prefix for S3 bucket name (must be globally unique)"
  type        = string
  default     = "obsidian-sync"
}

variable "iam_user_name" {
  description = "Name of the IAM user for Obsidian sync"
  type        = string
  default     = "obsidian-sync-user"
}

variable "vault_path" {
  description = "Subdirectory in bucket for vault contents"
  type        = string
  default     = "vault"
}

variable "noncurrent_version_expiration_days" {
  description = "Days to retain noncurrent versions (0 = disable lifecycle)"
  type        = number
  default     = 30
}

variable "enable_mfa_delete" {
  description = "Enable MFA delete for bucket (requires root MFA)"
  type        = bool
  default     = false
}

variable "seed_vault_path" {
  description = "Local path to seed vault contents (optional)"
  type        = string
  default     = ""
}
