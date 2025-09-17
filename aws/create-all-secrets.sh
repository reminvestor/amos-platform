#!/bin/bash

# Create all required secrets in AWS Secrets Manager

REGION="us-east-1"

# Load .env file
if [ -f ../.env ]; then
    source ../.env
else
    echo "Error: .env file not found"
    exit 1
fi

echo "Creating/updating secrets in AWS Secrets Manager..."

# Mailgun secrets (already created, but let's ensure they're up to date)
if [ ! -z "$MAILGUN_API_KEY" ]; then
    echo "Creating/updating Mailgun API key..."
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-mailgun-api-key" \
        --secret-string "$MAILGUN_API_KEY" \
        --region $REGION 2>/dev/null || \
    aws secretsmanager create-secret \
        --name "agent-marketing-mailgun-api-key" \
        --secret-string "$MAILGUN_API_KEY" \
        --region $REGION
fi

if [ ! -z "$MAILGUN_DOMAIN" ]; then
    echo "Creating/updating Mailgun domain..."
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-mailgun-domain" \
        --secret-string "$MAILGUN_DOMAIN" \
        --region $REGION 2>/dev/null || \
    aws secretsmanager create-secret \
        --name "agent-marketing-mailgun-domain" \
        --secret-string "$MAILGUN_DOMAIN" \
        --region $REGION
fi

# Pinecone secrets
if [ ! -z "$PINECONE_API_KEY" ]; then
    echo "Creating/updating Pinecone API key..."
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-pinecone-api-key" \
        --secret-string "$PINECONE_API_KEY" \
        --region $REGION 2>/dev/null || \
    aws secretsmanager create-secret \
        --name "agent-marketing-pinecone-api-key" \
        --secret-string "$PINECONE_API_KEY" \
        --region $REGION
fi

if [ ! -z "$PINECONE_ENVIRONMENT" ]; then
    echo "Creating/updating Pinecone environment..."
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-pinecone-environment" \
        --secret-string "$PINECONE_ENVIRONMENT" \
        --region $REGION 2>/dev/null || \
    aws secretsmanager create-secret \
        --name "agent-marketing-pinecone-environment" \
        --secret-string "$PINECONE_ENVIRONMENT" \
        --region $REGION
fi

if [ ! -z "$PINECONE_INDEX_NAME" ]; then
    echo "Creating/updating Pinecone index name..."
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-pinecone-index-name" \
        --secret-string "$PINECONE_INDEX_NAME" \
        --region $REGION 2>/dev/null || \
    aws secretsmanager create-secret \
        --name "agent-marketing-pinecone-index-name" \
        --secret-string "$PINECONE_INDEX_NAME" \
        --region $REGION
fi

# OpenAI secret
if [ ! -z "$OPENAI_API_KEY" ]; then
    echo "Creating/updating OpenAI API key..."
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-openai-api-key" \
        --secret-string "$OPENAI_API_KEY" \
        --region $REGION 2>/dev/null || \
    aws secretsmanager create-secret \
        --name "agent-marketing-openai-api-key" \
        --secret-string "$OPENAI_API_KEY" \
        --region $REGION
fi

# Anthropic secret
if [ ! -z "$ANTHROPIC_API_KEY" ]; then
    echo "Creating/updating Anthropic API key..."
    aws secretsmanager put-secret-value \
        --secret-id "agent-marketing-anthropic-api-key" \
        --secret-string "$ANTHROPIC_API_KEY" \
        --region $REGION 2>/dev/null || \
    aws secretsmanager create-secret \
        --name "agent-marketing-anthropic-api-key" \
        --secret-string "$ANTHROPIC_API_KEY" \
        --region $REGION
fi

echo ""
echo "✅ Secrets created/updated successfully!"
echo ""
echo "Next steps:"
echo "1. Update aws/terraform/main.tf to include the new secrets in the IAM policy"
echo "2. Update aws/terraform/main.tf to add the secrets to the ECS task definition"
echo "3. Run: terraform apply"
echo "4. Commit and push to trigger CodePipeline deployment"
