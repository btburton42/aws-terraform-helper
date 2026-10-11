#!/bin/bash
set -euo pipefail

# Script to seed Obsidian vault to S3
# Usage: ./seed-vault.sh <s3_uri> <local_path> [aws_profile]

S3_URI="${1:-}"
LOCAL_PATH="${2:-}"
AWS_PROFILE="${3:-obsidian-sync-user}"

if [[ -z "$S3_URI" || -z "$LOCAL_PATH" ]]; then
    echo "Usage: $0 <s3_uri> <local_path> [aws_profile]"
    echo "Example: $0 s3://my-bucket/vault ~/Documents/Obsidian"
    exit 1
fi

if [[ ! -d "$LOCAL_PATH" ]]; then
    echo "Error: Local path does not exist: $LOCAL_PATH"
    exit 1
fi

echo "=== Seeding Obsidian Vault ==="
echo "Source: $LOCAL_PATH"
echo "Destination: $S3_URI"
echo "Profile: $AWS_PROFILE"
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    echo "Error: AWS credentials not configured for profile '$AWS_PROFILE'"
    echo "Run: aws configure --profile $AWS_PROFILE"
    exit 1
fi

# Count files to upload
FILE_COUNT=$(find "$LOCAL_PATH" -type f | wc -l)
echo "Found $FILE_COUNT files to sync"
echo ""

# Perform sync with exclusions
echo "Starting sync (this may take a while)..."
aws s3 sync "$LOCAL_PATH" "$S3_URI" \
    --profile "$AWS_PROFILE" \
    --storage-class STANDARD \
    --sse AES256 \
    --exclude ".obsidian/*" \
    --exclude ".DS_Store" \
    --exclude "desktop.ini" \
    --exclude "*.tmp" \
    --exclude ".git/*" \
    --exclude ".Trash/*" \
    --delete

echo ""
echo "=== Sync Complete ==="

# Verify
REMOTE_COUNT=$(aws s3 ls "$S3_URI" --recursive --profile "$AWS_PROFILE" 2>/dev/null | wc -l)
echo "Files in S3: $REMOTE_COUNT"

if [[ "$FILE_COUNT" -eq "$REMOTE_COUNT" ]]; then
    echo "✓ All files uploaded successfully"
else
    echo "⚠ Warning: Local ($FILE_COUNT) and remote ($REMOTE_COUNT) counts differ"
    echo "  This may be due to excluded files (.obsidian, .DS_Store, etc.)"
fi
