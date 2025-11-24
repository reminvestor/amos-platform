# Data sources for externally managed secrets
data "aws_secretsmanager_secret" "pinecone_api_key" {
  name = "${var.app_name}-pinecone-api-key"
}

data "aws_secretsmanager_secret" "pinecone_environment" {
  name = "${var.app_name}-pinecone-environment"
}

data "aws_secretsmanager_secret" "pinecone_index_name" {
  name = "${var.app_name}-pinecone-index-name"
}

data "aws_secretsmanager_secret" "openai_api_key" {
  name = "${var.app_name}-openai-api-key"
}

data "aws_secretsmanager_secret" "anthropic_api_key" {
  name = "${var.app_name}-anthropic-api-key"
}

data "aws_secretsmanager_secret" "eleven_labs_api_key" {
  name = "${var.app_name}-eleven-labs-api-key"
}

data "aws_secretsmanager_secret" "serper_api_key" {
  name = "${var.app_name}-serper-api-key"
}

