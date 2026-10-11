# Obsidian S3 Sync Infrastructure

Terraform configuration for a secure, private S3 bucket to sync Obsidian vault files.

## Architecture

```
┌─────────────┐      HTTPS       ┌─────────────────────────────────────┐
│   Obsidian  │ ───────────────→ │  Private S3 Bucket                  │
│   (Desktop) │   (Direct S3     │  - Versioning: Enabled              │
│   (Mobile)  │    Endpoint)     │  - Encryption: SSE-S3 (AES-256)     │
│             │                  │  - Public Access: Blocked           │
│             │                  │  - CORS: Configured                 │
└─────────────┘                  │  - Lifecycle: 30-day cleanup        │
                                 └─────────────────────────────────────┘
                                          │
                                          ▼
                                 ┌─────────────────┐
                                 │  IAM User       │
                                 │  (obsidian-     │
                                 │   sync-user)    │
                                 │  - Programmatic │
                                 │    access only  │
                                 │  - Least        │
                                 │    privilege    │
                                 └─────────────────┘
```

## Quick Start

### 1. Prerequisites

- AWS CLI v2 installed: `aws --version`
- Terraform >= 1.0 installed: `terraform -version`
- AWS account with programmatic access

### 2. Configure AWS CLI

```bash
# Configure with your admin credentials (or use default profile)
aws configure
# AWS Access Key ID: [your-admin-key]
# AWS Secret Access Key: [your-admin-secret]
# Default region: us-east-1
```

### 3. Deploy Infrastructure

```bash
# Copy example variables and customize
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars if desired

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Deploy
cd /home/papa/Repos/aws-helper && terraform apply

# Save the outputs securely!
terraform output -raw secret_access_key > ~/.obsidian-secret-key
chmod 600 ~/.obsidian-secret-key
```

### 4. Configure Obsidian Remotely Save Plugin

1. Install "Remotely Save" plugin in Obsidian
2. Open Settings → Remotely Save
3. Configure:

| Setting | Value |
|---------|-------|
| **Service Type** | S3 |
| **Endpoint** | `https://s3.us-east-1.amazonaws.com` (or your region) |
| **Region** | `us-east-1` (or your configured region) |
| **Access Key ID** | From `terraform output access_key_id` |
| **Secret Access Key** | From `terraform output -raw secret_access_key` |
| **Bucket Name** | From `terraform output bucket_name` |
| **Path Prefix** | `vault/` (or your configured vault_path) |
| **Force Path Style** | `false` |
| **Disable S3 URI Encoding** | `false` |

4. Test connection → Check sync

## Seeding Your Vault (Method 1 - AWS CLI)

To upload an existing Obsidian vault to S3 before configuring the plugin:

### Step 1: Configure AWS CLI with Obsidian Credentials

```bash
aws configure --profile obsidian-sync-user
# Access Key ID: (from terraform output)
# Secret Access Key: (from terraform output)
# Region: us-east-1
# Output: json
```

### Step 2: Sync Your Vault

```bash
# Set variables
BUCKET_NAME=$(terraform output -raw bucket_name)
VAULT_PATH="vault"  # or your configured path
LOCAL_VAULT="$HOME/Documents/Obsidian"  # adjust to your vault location

# Perform sync (only uploads changed files on subsequent runs)
aws s3 sync "$LOCAL_VAULT" "s3://${BUCKET_NAME}/${VAULT_PATH}/" \
    --profile obsidian-sync-user \
    --storage-class STANDARD \
    --sse AES256 \
    --exclude ".obsidian/*" \
    --exclude ".DS_Store" \
    --exclude "*.tmp" \
    --delete

# With progress bar for large vaults
aws s3 sync "$LOCAL_VAULT" "s3://${BUCKET_NAME}/${VAULT_PATH}/" \
    --profile obsidian-sync-user \
    --storage-class STANDARD \
    --sse AES256 \
    --exclude ".obsidian/*" \
    --progress
```

### Step 3: Verify Upload

```bash
# List uploaded files
aws s3 ls "s3://${BUCKET_NAME}/${VAULT_PATH}/" --recursive --profile obsidian-sync-user

# Count files
aws s3 ls "s3://${BUCKET_NAME}/${VAULT_PATH}/" --recursive --profile obsidian-sync-user | wc -l
```

### Alternative: Use the Helper Script

```bash
# Run with parameters
./scripts/seed-vault.sh \
    "s3://$(terraform output -raw bucket_name)/vault" \
    "$HOME/Documents/Obsidian" \
    obsidian-sync-user
```

### Sync Options Explained

| Option | Purpose |
|--------|---------|
| `--exclude ".obsidian/*"` | Skip Obsidian system files (plugins, settings) |
| `--exclude ".DS_Store"` | Skip macOS system files |
| `--delete` | Remove files from S3 that were deleted locally |
| `--storage-class STANDARD` | Use standard storage (not Glacier) |
| `--sse AES256` | Server-side encryption |
| `--profile obsidian-sync-user` | Use the dedicated IAM user |

## Security Features

- **Private bucket**: No public access, blocked at account and bucket level
- **Encryption**: AES-256 server-side encryption
- **Versioning**: Recover deleted files for 30 days (configurable)
- **Least privilege**: IAM user can only access this specific bucket
- **HTTPS only**: Bucket policy denies HTTP requests
- **No root credentials**: Uses dedicated IAM user with minimal permissions

## Rotation Strategy

### Rotate Access Keys (if compromised)

```bash
# Create new key
terraform apply -replace=aws_iam_access_key.obsidian

# Update Obsidian with new credentials from terraform output

# Old key is automatically destroyed
```

### Rotate Bucket (if needed)

```bash
# Create new bucket
terraform apply -var="bucket_prefix=obsidian-sync-v2"

# Sync data to new bucket
aws s3 sync "s3://old-bucket/vault/" "s3://new-bucket/vault/" --profile obsidian-sync-user

# Update Obsidian with new bucket name
# Destroy old bucket when confirmed
terraform destroy -target=aws_s3_bucket.obsidian
```

## Maintenance

### Check Storage Costs

```bash
# Get bucket size
aws s3api list-objects --bucket $(terraform output -raw bucket_name) \
    --output json --query "[sum(Contents[].Size)]" | awk '{print $1/1024/1024/1024 " GB"}'
```

### List All Versions (to see deleted files)

```bash
aws s3api list-object-versions --bucket $(terraform output -raw bucket_name) \
    --prefix vault/ | jq -r '.Versions[] | select(.IsLatest==false) | .Key'
```

## Cleanup

```bash
# Destroy all resources (irreversible!)
terraform destroy

# Or destroy just the bucket (retain IAM user)
terraform destroy -target=aws_s3_bucket.obsidian
```

## Troubleshooting

### Access Denied Error

- Verify AWS CLI profile is configured: `aws sts get-caller-identity --profile obsidian-sync-user`
- Check credentials match terraform output
- Ensure bucket policy allows HTTPS only (not HTTP)

### Sync Shows No Progress

- Large files: Add `--cli-read-timeout 0 --cli-connect-timeout 0`
- Check AWS CLI version: `aws --version` (should be v2)

### Files Not Appearing in Obsidian

- Check path prefix matches (e.g., `vault/` vs `vault`)
- Verify CORS configuration allows your client
- Check Remotely Save console for errors

## Cost Estimate

| Component | Monthly Cost |
|-----------|--------------|
| 10GB storage | ~$0.23 |
| 10,000 PUT requests | ~$0.05 |
| 10,000 GET requests | ~$0.004 |
| 1GB data transfer | ~$0.09 |
| **Total** | **~$0.37** |

## Files Generated

After `terraform apply`, you'll find:

- `obsidian-config-<bucket-name>.txt` - Configuration for Obsidian plugin (chmod 600)
- `config-template.txt` - Template for generating configs
- `terraform.tfstate` - Terraform state (keep secure, use remote backend for teams)

## Support

- AWS S3 Pricing: https://aws.amazon.com/s3/pricing/
- Remotely Save Plugin: https://github.com/remotely-save/remotely-save
- Terraform AWS Provider: https://registry.terraform.io/providers/hashicorp/aws/latest/docs
