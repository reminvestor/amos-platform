# terraform/modules/iam/main.tf
# IAM Roles and Policies Module

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Bedrock Knowledge Base Execution Role
resource "aws_iam_role" "bedrock_kb" {
  name = "${var.project_name}-${var.environment}-bedrock-kb-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-bedrock-kb-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Bedrock KB S3 Access Policy
resource "aws_iam_role_policy" "bedrock_kb_s3" {
  name = "${var.project_name}-${var.environment}-bedrock-kb-s3-policy"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          var.bedrock_kb_bucket_arn,
          "${var.bedrock_kb_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Bedrock KB OpenSearch Access Policy
resource "aws_iam_role_policy" "bedrock_kb_opensearch" {
  name = "${var.project_name}-${var.environment}-bedrock-kb-opensearch-policy"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll"
        ]
        Resource = var.opensearch_domain_arn
      }
    ]
  })
}

# Bedrock KB Model Access Policy
resource "aws_iam_role_policy" "bedrock_kb_model" {
  name = "${var.project_name}-${var.environment}-bedrock-kb-model-policy"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/*"
        ]
      }
    ]
  })
}

# Lambda Execution Role
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-lambda-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Lambda Basic Execution Policy
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# Lambda Bedrock Access Policy
resource "aws_iam_role_policy" "lambda_bedrock" {
  name = "${var.project_name}-${var.environment}-lambda-bedrock-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock-agent:Retrieve",
          "bedrock-agent:RetrieveAndGenerate",
          "bedrock-agent:StartIngestionJob",
          "bedrock-agent:GetIngestionJob",
          "bedrock-agent:ListIngestionJobs"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Textract Access Policy
resource "aws_iam_role_policy" "lambda_textract" {
  name = "${var.project_name}-${var.environment}-lambda-textract-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "textract:DetectDocumentText",
          "textract:AnalyzeDocument",
          "textract:AnalyzeExpense",
          "textract:AnalyzeID",
          "textract:StartDocumentTextDetection",
          "textract:GetDocumentTextDetection",
          "textract:StartDocumentAnalysis",
          "textract:GetDocumentAnalysis"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda Comprehend Access Policy
resource "aws_iam_role_policy" "lambda_comprehend" {
  name = "${var.project_name}-${var.environment}-lambda-comprehend-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "comprehend:DetectEntities",
          "comprehend:DetectKeyPhrases",
          "comprehend:DetectSentiment",
          "comprehend:DetectSyntax",
          "comprehend:DetectDominantLanguage",
          "comprehend:DetectPiiEntities",
          "comprehend:ClassifyDocument"
        ]
        Resource = "*"
      }
    ]
  })
}

# Lambda S3 Access Policy
resource "aws_iam_role_policy" "lambda_s3" {
  name = "${var.project_name}-${var.environment}-lambda-s3-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.bedrock_kb_bucket_arn,
          "${var.bedrock_kb_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Lambda KMS Access Policy
resource "aws_iam_role_policy" "lambda_kms" {
  name = "${var.project_name}-${var.environment}-lambda-kms-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# Application Execution Role (for Rails app on ECS/EC2)
resource "aws_iam_role" "application" {
  name = "${var.project_name}-${var.environment}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com",
            "ecs-tasks.amazonaws.com"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-${var.environment}-app-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Application Bedrock Access Policy
resource "aws_iam_role_policy" "app_bedrock" {
  name = "${var.project_name}-${var.environment}-app-bedrock-policy"
  role = aws_iam_role.application.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock-agent:Retrieve",
          "bedrock-agent:RetrieveAndGenerate",
          "bedrock-agent:StartIngestionJob",
          "bedrock-agent:GetIngestionJob",
          "bedrock-agent:ListIngestionJobs",
          "bedrock-agent:CreateKnowledgeBase",
          "bedrock-agent:UpdateKnowledgeBase",
          "bedrock-agent:GetKnowledgeBase",
          "bedrock-agent:ListKnowledgeBases"
        ]
        Resource = "*"
      }
    ]
  })
}

# Application Textract Access Policy
resource "aws_iam_role_policy" "app_textract" {
  name = "${var.project_name}-${var.environment}-app-textract-policy"
  role = aws_iam_role.application.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "textract:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Application Comprehend Access Policy
resource "aws_iam_role_policy" "app_comprehend" {
  name = "${var.project_name}-${var.environment}-app-comprehend-policy"
  role = aws_iam_role.application.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "comprehend:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# Application S3 Access Policy
resource "aws_iam_role_policy" "app_s3" {
  name = "${var.project_name}-${var.environment}-app-s3-policy"
  role = aws_iam_role.application.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*"
        ]
        Resource = [
          var.bedrock_kb_bucket_arn,
          "${var.bedrock_kb_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Application CloudWatch Access Policy
resource "aws_iam_role_policy" "app_cloudwatch" {
  name = "${var.project_name}-${var.environment}-app-cloudwatch-policy"
  role = aws_iam_role.application.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile for EC2
resource "aws_iam_instance_profile" "application" {
  name = "${var.project_name}-${var.environment}-app-instance-profile"
  role = aws_iam_role.application.name
}

# Outputs
output "bedrock_kb_role_arn" {
  value       = aws_iam_role.bedrock_kb.arn
  description = "ARN of the Bedrock Knowledge Base role"
}

output "lambda_role_arn" {
  value       = aws_iam_role.lambda.arn
  description = "ARN of the Lambda execution role"
}

output "application_role_arn" {
  value       = aws_iam_role.application.arn
  description = "ARN of the application execution role"
}

output "application_instance_profile_name" {
  value       = aws_iam_instance_profile.application.name
  description = "Name of the application instance profile"
}