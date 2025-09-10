#!/bin/bash
set -e

echo "🚀 Preparing source code for CodePipeline deployment..."

# Get the source bucket from Terraform output
cd aws/terraform
SOURCE_BUCKET=$(terraform output -raw source_bucket)
cd ../..

# Create a temporary directory for the source
TEMP_DIR=$(mktemp -d)
echo "📦 Creating source package in $TEMP_DIR..."

# Copy all files except excluded ones
rsync -av --exclude='.git' \
          --exclude='node_modules' \
          --exclude='tmp' \
          --exclude='log' \
          --exclude='storage' \
          --exclude='vendor/bundle' \
          --exclude='.terraform' \
          --exclude='*.tfstate*' \
          --exclude='aws/terraform/.terraform' \
          . "$TEMP_DIR/"

# Create the zip file
cd "$TEMP_DIR"
zip -r source.zip . -x "*.git*" "node_modules/*" "tmp/*" "log/*" "storage/*" "vendor/bundle/*" ".terraform/*" "*.tfstate*"

# Upload to S3
echo "📤 Uploading source.zip to S3 bucket: $SOURCE_BUCKET"
aws s3 cp source.zip "s3://$SOURCE_BUCKET/source.zip"

# Clean up
cd -
rm -rf "$TEMP_DIR"

echo "✅ Source code uploaded successfully!"
echo ""
echo "🔄 The CodePipeline should start automatically."
echo "📊 Monitor progress at: https://console.aws.amazon.com/codesuite/codepipeline/pipelines/agent-marketing-pipeline/view"
echo ""
echo "Note: The first deployment may take 10-15 minutes to complete."
