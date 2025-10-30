# S3 Bucket for RAG Document Storage
# This bucket stores raw documents, processed chunks, and Docling output
# Structure: s3://bucket/entities/{entity_id}/ and s3://bucket/system/

resource "aws_s3_bucket" "rag_storage" {
  bucket = "${var.app_name}-rag-storage-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.app_name} RAG Storage"
    Environment = var.environment
    Purpose     = "RAG document storage - raw processed and docling output"
  }
}

# Enable versioning for document history
resource "aws_s3_bucket_versioning" "rag_storage" {
  bucket = aws_s3_bucket.rag_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "rag_storage" {
  bucket = aws_s3_bucket.rag_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "rag_storage" {
  bucket = aws_s3_bucket.rag_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "rag_storage" {
  bucket = aws_s3_bucket.rag_storage.id

  # Archive entity raw documents to Glacier for cost optimization
  # Keep forever - only delete when entity is explicitly deleted by app
  rule {
    id     = "archive-entity-documents"
    status = "Enabled"

    filter {
      prefix = "entities/"
    }

    # Move to cheaper storage after 90 days (cost optimization)
    transition {
      days          = 90
      storage_class = "INTELLIGENT_TIERING" # Auto-optimizes between frequent/infrequent access
    }

    # Keep old versions for 30 days then delete (versioning cleanup)
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # Keep system documents (AMOS knowledge) indefinitely in Standard
  rule {
    id     = "retain-system-documents"
    status = "Enabled"

    filter {
      prefix = "system/"
    }

    # Keep old versions for 30 days then delete (versioning cleanup)
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # Clean up temporary files after 7 days
  rule {
    id     = "cleanup-temp-files"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    expiration {
      days = 7
    }
  }
}

# CORS configuration for browser uploads (if using presigned URLs)
resource "aws_s3_bucket_cors_configuration" "rag_storage" {
  bucket = aws_s3_bucket.rag_storage.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = [
      var.domain_name != "" ? "https://app.${var.domain_name}" : "http://localhost:3000",
      var.domain_name != "" ? "https://www.${var.domain_name}" : ""
    ]
    expose_headers  = ["ETag", "Content-Length"]
    max_age_seconds = 3000
  }
}

# Outputs
output "rag_bucket_name" {
  value       = aws_s3_bucket.rag_storage.id
  description = "S3 bucket for RAG document storage"
}

output "rag_bucket_arn" {
  value       = aws_s3_bucket.rag_storage.arn
  description = "ARN of RAG storage bucket"
}
