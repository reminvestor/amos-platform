# terraform/modules/bedrock/main.tf
# Bedrock Knowledge Base Module

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Bedrock Agent (Knowledge Base)
resource "aws_bedrockagent_knowledge_base" "main" {
  name        = var.knowledge_base_name
  description = var.knowledge_base_description
  role_arn    = var.role_arn

  knowledge_base_configuration {
    type = "VECTOR"

    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.embedding_model}"

      embedding_model_configuration {
        bedrock_embedding_model_configuration {
          dimensions = var.embedding_model == "amazon.titan-embed-text-v2:0" ? 1024 : 1536
        }
      }
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"

    opensearch_serverless_configuration {
      collection_arn    = var.opensearch_collection_id
      vector_index_name = var.opensearch_index_name

      field_mapping {
        vector_field   = "embedding"
        text_field     = "text"
        metadata_field = "metadata"
      }
    }
  }

  tags = {
    Name        = var.knowledge_base_name
    Environment = var.environment
    Project     = var.project_name
  }
}

# Data Source for Knowledge Base
resource "aws_bedrockagent_data_source" "main" {
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  name              = "${var.knowledge_base_name}-datasource"
  description       = "S3 data source for ${var.knowledge_base_name}"

  data_source_configuration {
    type = "S3"

    s3_configuration {
      bucket_arn = var.s3_bucket_arn

      inclusion_prefixes = [
        "documents/",
        "processed/"
      ]

      exclusion_patterns = [
        "*.tmp",
        "*.log",
        ".metadata.json"
      ]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"

      fixed_size_chunking_configuration {
        max_tokens         = var.chunk_size
        overlap_percentage = var.chunk_overlap_percentage
      }
    }

    parsing_configuration {
      parsing_strategy = "BEDROCK_FOUNDATION_MODEL"

      bedrock_foundation_model_configuration {
        model_arn = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/anthropic.claude-3-haiku-20240307-v1:0"

        parsing_prompt {
          parsing_prompt_text = var.parsing_prompt
        }
      }
    }
  }
}

# Lambda function for processing documents
resource "aws_lambda_function" "document_processor" {
  filename         = "${path.module}/lambda/document_processor.zip"
  function_name    = "${var.project_name}-${var.environment}-doc-processor"
  role            = var.lambda_role_arn
  handler         = "index.handler"
  runtime         = "python3.11"
  timeout         = 300
  memory_size     = 1024

  environment {
    variables = {
      KNOWLEDGE_BASE_ID = aws_bedrockagent_knowledge_base.main.id
      S3_BUCKET        = var.s3_bucket_name
      REGION           = data.aws_region.current.name
    }
  }

  layers = [
    "arn:aws:lambda:${data.aws_region.current.name}:336392948345:layer:AWSSDKPandas-Python311:1"
  ]

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-doc-processor"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Security group for Lambda
resource "aws_security_group" "lambda" {
  name        = "${var.project_name}-${var.environment}-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# S3 trigger for Lambda
resource "aws_s3_bucket_notification" "document_upload" {
  bucket = var.s3_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.document_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".pdf"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.document_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".txt"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Permission for S3 to invoke Lambda
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.document_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.s3_bucket_arn
}

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.document_processor.function_name}"
  retention_in_days = var.log_retention_days
  kms_key_id       = var.kms_key_id

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-logs"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Data sources
data "aws_region" "current" {}

# Outputs
output "knowledge_base_id" {
  value       = aws_bedrockagent_knowledge_base.main.id
  description = "ID of the Bedrock Knowledge Base"
}

output "knowledge_base_arn" {
  value       = aws_bedrockagent_knowledge_base.main.arn
  description = "ARN of the Bedrock Knowledge Base"
}

output "data_source_id" {
  value       = aws_bedrockagent_data_source.main.id
  description = "ID of the Knowledge Base data source"
}

output "document_processor_function_name" {
  value       = aws_lambda_function.document_processor.function_name
  description = "Name of the document processor Lambda function"
}

output "document_processor_function_arn" {
  value       = aws_lambda_function.document_processor.arn
  description = "ARN of the document processor Lambda function"
}