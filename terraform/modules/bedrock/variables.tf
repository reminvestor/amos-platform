# terraform/modules/bedrock/variables.tf
# Variables for Bedrock Knowledge Base Module

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "knowledge_base_name" {
  description = "Name of the Bedrock Knowledge Base"
  type        = string
}

variable "knowledge_base_description" {
  description = "Description of the Bedrock Knowledge Base"
  type        = string
}

variable "role_arn" {
  description = "IAM role ARN for Bedrock Knowledge Base"
  type        = string
}

variable "opensearch_collection_id" {
  description = "OpenSearch Serverless collection ID"
  type        = string
}

variable "opensearch_index_name" {
  description = "OpenSearch index name"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of S3 bucket for documents"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of S3 bucket for documents"
  type        = string
}

variable "embedding_model" {
  description = "Embedding model to use"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "chunk_size" {
  description = "Size of text chunks in tokens"
  type        = number
  default     = 512
}

variable "chunk_overlap_percentage" {
  description = "Percentage of overlap between chunks"
  type        = number
  default     = 20
}

variable "parsing_prompt" {
  description = "Prompt for parsing documents"
  type        = string
  default     = "Extract the text content from this document, preserving the structure and important information."
}

variable "lambda_role_arn" {
  description = "IAM role ARN for Lambda function"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for Lambda function"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Lambda function"
  type        = list(string)
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "kms_key_id" {
  description = "KMS key ID for encryption"
  type        = string
}