# terraform/main.tf
# Main Terraform configuration for Agent Marketing AWS Infrastructure

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # S3 backend for state management
  backend "s3" {
    bucket         = "agent-marketing-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

# Configure AWS Provider
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "AgentMarketing"
      Environment = var.environment
      ManagedBy   = "Terraform"
      CostCenter  = var.cost_center
    }
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# KMS Key for encryption
resource "aws_kms_key" "main" {
  description             = "KMS key for ${var.project_name} ${var.environment}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${var.project_name}-${var.environment}-kms"
  }
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project_name}-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}

# VPC Module
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr

  availability_zones = var.availability_zones
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
}

# S3 Buckets for RAG/Document Storage
module "s3_storage" {
  source = "./modules/s3"

  project_name = var.project_name
  environment  = var.environment
  kms_key_id   = aws_kms_key.main.id

  rag_bucket_name = var.rag_bucket_name
  enable_versioning = true
  enable_lifecycle  = true
  enable_intelligent_tiering = true
}

# IAM Roles and Policies
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment

  bedrock_kb_bucket_arn = module.s3_storage.rag_bucket_arn
  opensearch_domain_arn = module.opensearch.domain_arn
  kms_key_arn          = aws_kms_key.main.arn
}

# OpenSearch Serverless for Bedrock KB
module "opensearch" {
  source = "./modules/opensearch"

  project_name = var.project_name
  environment  = var.environment

  collection_name = "${var.project_name}-${var.environment}-kb"
  kms_key_id     = aws_kms_key.main.id
}

# Bedrock Knowledge Base
module "bedrock_kb" {
  source = "./modules/bedrock"

  project_name = var.project_name
  environment  = var.environment

  knowledge_base_name        = "${var.project_name}-${var.environment}-kb"
  knowledge_base_description = "Knowledge base for ${var.project_name} ${var.environment}"

  role_arn                = module.iam.bedrock_kb_role_arn
  opensearch_collection_id = module.opensearch.collection_id
  opensearch_index_name   = "${var.project_name}-${var.environment}-index"

  s3_bucket_arn = module.s3_storage.rag_bucket_arn
  s3_bucket_name = module.s3_storage.rag_bucket_name

  embedding_model = var.bedrock_embedding_model
}

# Lambda Functions for Async Processing
module "lambda" {
  source = "./modules/lambda"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids

  kms_key_id = aws_kms_key.main.id

  # Environment variables for Lambda functions
  environment_variables = {
    BEDROCK_KB_ID     = module.bedrock_kb.knowledge_base_id
    S3_BUCKET        = module.s3_storage.rag_bucket_name
    OPENSEARCH_ENDPOINT = module.opensearch.endpoint
    AWS_REGION       = var.aws_region
  }
}

# CloudWatch Log Groups
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name = var.project_name
  environment  = var.environment

  retention_days = var.log_retention_days
  kms_key_id    = aws_kms_key.main.id
}

# Cost Monitoring and Budgets
module "cost_management" {
  source = "./modules/cost_management"

  project_name = var.project_name
  environment  = var.environment

  monthly_budget_amount = var.monthly_budget_amount
  alert_email_addresses = var.alert_email_addresses
}

# Secrets Manager for API Keys
resource "aws_secretsmanager_secret" "api_keys" {
  name                    = "${var.project_name}-${var.environment}-api-keys"
  description            = "API keys for ${var.project_name} ${var.environment}"
  recovery_window_in_days = 7
  kms_key_id             = aws_kms_key.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-api-keys"
  }
}

# ECR Repository for Docker Images (Main App)
resource "aws_ecr_repository" "app" {
  name                 = "${var.project_name}-${var.environment}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key        = aws_kms_key.main.arn
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR Repository for Agent Lightning (Python Service)
resource "aws_ecr_repository" "agent_lightning" {
  name                 = "${var.project_name}-${var.environment}-agent-lightning"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key        = aws_kms_key.main.arn
  }

  lifecycle_policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# SNS Topics for Alerts
resource "aws_sns_topic" "alerts" {
  name              = "${var.project_name}-${var.environment}-alerts"
  kms_master_key_id = aws_kms_key.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-alerts"
  }
}

resource "aws_sns_topic_subscription" "alert_emails" {
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# ElastiCache Redis Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-redis-subnet"
  subnet_ids = module.vpc.private_subnet_ids
}

# Security Group for Redis
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Security group for Redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # Allow access from within VPC
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-redis-sg"
  }
}

# ElastiCache Redis Cluster (Replication Group)
resource "aws_elasticache_replication_group" "main" {
  replication_group_id          = "${var.project_name}-${var.environment}-redis"
  replication_group_description = "Redis cluster for ${var.project_name} ${var.environment}"
  node_type                     = "cache.t3.micro" # Free tier eligible-ish
  port                          = 6379
  parameter_group_name          = "default.redis7"
  automatic_failover_enabled    = true
  num_node_groups               = 1
  replicas_per_node_group       = 1
  subnet_group_name             = aws_elasticache_subnet_group.main.name
  security_group_ids            = [aws_security_group.redis.id]
  at_rest_encryption_enabled    = true
  transit_encryption_enabled    = true
  kms_key_id                    = aws_kms_key.main.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-redis"
  }
}

# Outputs
output "vpc_id" {
  value = module.vpc.vpc_id
}

output "bedrock_knowledge_base_id" {
  value = module.bedrock_kb.knowledge_base_id
}

output "s3_rag_bucket_name" {
  value = module.s3_storage.rag_bucket_name
}

output "opensearch_endpoint" {
  value = module.opensearch.endpoint
}

output "sns_alert_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "agent_lightning_ecr_repository_url" {
  value = aws_ecr_repository.agent_lightning.repository_url
}
