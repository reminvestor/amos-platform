#!/bin/bash

# Wait for LocalStack to be ready
echo "Waiting for LocalStack to be ready..."
for i in {1..30}; do
  if aws --endpoint-url=http://localhost:4566 s3 ls 2>/dev/null; then
    echo "LocalStack is ready!"
    break
  fi
  echo "Attempt $i: Waiting for LocalStack..."
  sleep 2
done

# Create S3 bucket
echo "Creating S3 bucket..."
aws --endpoint-url=http://localhost:4566 s3 mb s3://agent-marketing-rag-storage --region us-east-1 2>/dev/null || echo "Bucket may already exist"

echo "S3 initialization complete!"
