#!/bin/bash
# scripts/test-infrastructure.sh
# Test AWS Bedrock infrastructure

set -e

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}ℹ ${NC}$1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }

ENVIRONMENT=${1:-dev}
TERRAFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/terraform"

print_info "Testing ${ENVIRONMENT} infrastructure..."
echo ""

cd "$TERRAFORM_DIR"

# Get outputs
KB_ID=$(terraform output -raw bedrock_knowledge_base_id 2>/dev/null || echo "")
BUCKET=$(terraform output -raw s3_rag_bucket_name 2>/dev/null || echo "")
OPENSEARCH=$(terraform output -raw opensearch_endpoint 2>/dev/null || echo "")

if [ -z "$KB_ID" ]; then
    print_error "Knowledge Base ID not found. Has Terraform been applied?"
    exit 1
fi

print_info "Testing components:"
echo ""

# Test 1: S3 Bucket Access
print_info "1. Testing S3 bucket access..."
if aws s3 ls "s3://${BUCKET}/" &>/dev/null; then
    print_success "S3 bucket accessible: ${BUCKET}"
else
    print_error "Cannot access S3 bucket: ${BUCKET}"
fi

# Test 2: Knowledge Base exists
print_info "2. Testing Bedrock Knowledge Base..."
if aws bedrock-agent get-knowledge-base --knowledge-base-id "$KB_ID" &>/dev/null; then
    print_success "Knowledge Base accessible: ${KB_ID}"
else
    print_error "Cannot access Knowledge Base: ${KB_ID}"
fi

# Test 3: Upload test document
print_info "3. Testing document upload..."
TEST_FILE="/tmp/test-kb-doc.txt"
echo "This is a test document for Bedrock Knowledge Base." > "$TEST_FILE"
echo "It contains sample text for testing the RAG pipeline." >> "$TEST_FILE"

if aws s3 cp "$TEST_FILE" "s3://${BUCKET}/test/test-doc.txt" &>/dev/null; then
    print_success "Test document uploaded successfully"
else
    print_error "Failed to upload test document"
fi
rm -f "$TEST_FILE"

# Test 4: Textract API
print_info "4. Testing Textract API..."
if aws textract detect-document-text --document '{"S3Object":{"Bucket":"'${BUCKET}'","Name":"test/test-doc.txt"}}' &>/dev/null; then
    print_success "Textract API accessible"
else
    print_error "Textract API not accessible"
fi

# Test 5: Comprehend API
print_info "5. Testing Comprehend API..."
if aws comprehend detect-sentiment --text "This is a test" --language-code "en" &>/dev/null; then
    print_success "Comprehend API accessible"
else
    print_error "Comprehend API not accessible"
fi

# Test 6: Bedrock Model Access
print_info "6. Testing Bedrock model access..."
if aws bedrock list-foundation-models --by-provider anthropic &>/dev/null; then
    print_success "Bedrock models accessible"
else
    print_error "Bedrock models not accessible"
fi

echo ""
print_success "Infrastructure tests complete!"
echo ""

print_info "Infrastructure summary:"
echo "  Environment: ${ENVIRONMENT}"
echo "  Knowledge Base ID: ${KB_ID}"
echo "  S3 Bucket: ${BUCKET}"
echo "  OpenSearch: ${OPENSEARCH}"
echo ""

print_info "To test from Rails console:"
echo '  rails console'
echo '  entity = Entity.first'
echo '  kb = Aws::BedrockKnowledgeBaseService.instance'
echo "  kb.create_knowledge_base(entity)"
echo ""