#!/bin/bash

# Enable Public S3 Access and Fix Landing Page URLs
# Run this script from your local machine

set -e

BUCKET="${AWS_S3_BUCKET:-agent-marketing-rag-storage}"
REGION="${AWS_REGION:-us-east-1}"

echo "=========================================="
echo "🪣 S3 Bucket: $BUCKET"
echo "🌎 Region: $REGION"
echo "=========================================="

# Step 1: Disable Block Public Access
echo ""
echo "📝 Step 1: Disabling Block Public Access..."
aws s3api put-public-access-block \
    --bucket "$BUCKET" \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
    --region "$REGION"

echo "✅ Block Public Access disabled"

# Step 2: Add bucket policy for public reads
echo ""
echo "📝 Step 2: Adding public read bucket policy..."

cat > /tmp/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${BUCKET}/*"
        }
    ]
}
EOF

aws s3api put-bucket-policy \
    --bucket "$BUCKET" \
    --policy file:///tmp/bucket-policy.json \
    --region "$REGION"

echo "✅ Public read policy applied"

# Step 3: Verify
echo ""
echo "📝 Step 3: Verifying configuration..."
aws s3api get-bucket-policy --bucket "$BUCKET" --region "$REGION" | head -20

echo ""
echo "=========================================="
echo "✅ S3 bucket is now publicly readable!"
echo ""
echo "Now run this in your Rails production console to fix landing page URLs:"
echo ""
echo "  rails runner scripts/fix_landing_page_urls.rb"
echo ""
echo "Or via ECS:"
echo "  ./aws/rails-console.sh"
echo "  Then paste the Ruby code from scripts/fix_landing_page_urls.rb"
echo "=========================================="
