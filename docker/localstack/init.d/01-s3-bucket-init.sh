#!/bin/bash

# LocalStack S3 Bucket Initialization Script
# This script runs automatically when LocalStack starts

echo "=== LocalStack S3 Initialization ==="
echo "Creating RAG storage bucket..."

# Create the S3 bucket for RAG document storage
awslocal s3 mb s3://agent-marketing-rag-storage --region us-east-1 2>/dev/null && \
    echo "✅ S3 bucket 'agent-marketing-rag-storage' created successfully" || \
    echo "ℹ️ S3 bucket may already exist or creation failed"

# List buckets to verify
echo "Available S3 buckets:"
awslocal s3 ls

echo "=== S3 Initialization Complete ==="
