terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables
variable "aws_region" {
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "app_name" {
  description = "Application name"
  default     = "agent-marketing"
}

variable "environment" {
  description = "Environment name"
  default     = "production"
}

variable "domain_name" {
  description = "Domain name for the application"
  type        = string
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
  default     = "rickbarkley"
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
  default     = "agent_marketing"
}

variable "github_branch" {
  description = "GitHub branch to deploy from"
  type        = string
  default     = "main"
}

variable "github_token" {
  description = "GitHub personal access token for CodePipeline"
  type        = string
  sensitive   = true
  default     = ""
}

variable "mail_from_domain" {
  description = "Domain to use for sending emails (SES identity must be verified)"
  type        = string
  default     = "amoslabs.com"
}

variable "create_certificate" {
  description = "Whether to create ACM certificate (requires DNS validation)"
  type        = bool
  default     = true
}

variable "use_route53" {
  description = "Whether to use Route 53 for DNS (set to false if using external DNS like GoDaddy)"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "Skip final DB snapshot on destroy (useful for dev)"
  type        = bool
  default     = false
}

variable "enable_nat_gateway" {
  description = "Enable NAT Gateway for private subnets (expensive, disable for dev)"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on database"
  type        = bool
  default     = true
}

variable "multi_az" {
  description = "Enable Multi-AZ for RDS"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.small"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 50
}

variable "db_backup_retention_period" {
  description = "RDS backup retention period in days"
  type        = number
  default     = 7
}

variable "redis_node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t3.small"
}

variable "ecs_task_cpu" {
  description = "ECS task CPU units"
  type        = string
  default     = "4096"  # 4 vCPU for AI workloads
}

variable "ecs_task_memory" {
  description = "ECS task memory in MB"
  type        = string
  default     = "8192"  # 8 GB - Rails + Worker + AI models need more memory
}

variable "ecs_desired_count" {
  description = "Desired number of ECS tasks"
  type        = number
  default     = 1
}

variable "ecs_min_count" {
  description = "Minimum number of ECS tasks"
  type        = number
  default     = 1
}

variable "ecs_max_count" {
  description = "Maximum number of ECS tasks"
  type        = number
  default     = 4
}

# VPC Configuration
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.0.0"

  name = "${var.app_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = var.enable_nat_gateway
  enable_dns_hostnames = true

  tags = {
    Environment = var.environment
  }
}

# RDS PostgreSQL Database
resource "aws_db_subnet_group" "main" {
  name       = "${var.app_name}-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${var.app_name} DB subnet group"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.app_name}-rds"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres" {
  identifier     = "${var.app_name}-db"
  engine         = "postgres"
  engine_version = "15.12"
  instance_class = var.db_instance_class  # Consider upgrading to db.t3.small for RAG workload

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 5
  storage_encrypted     = true

  db_name  = "agent_marketing_${var.environment}"
  username = "postgres"
  password = random_password.db_password.result

  # Use custom parameter group with pgvector enabled (defined in rds.tf)
  parameter_group_name = aws_db_parameter_group.postgres_with_pgvector.name

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  multi_az = var.multi_az
  deletion_protection = var.enable_deletion_protection

  skip_final_snapshot = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.app_name}-final-snapshot-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"

  backup_retention_period = var.db_backup_retention_period
  backup_window          = "03:00-04:00"
  maintenance_window     = "sun:04:00-sun:05:00"

  # Allow modifications (parameter group change requires restart)
  apply_immediately = false

  tags = {
    Name        = "${var.app_name}-database"
    Environment = var.environment
    Extensions  = "pgvector"
  }
}

resource "random_password" "db_password" {
  length  = 32
  special = true
}

# S3 Bucket for Active Storage
resource "aws_s3_bucket" "storage" {
  bucket = "${var.app_name}-storage-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name        = "${var.app_name} Storage"
    Environment = var.environment
  }
}

resource "aws_s3_bucket_versioning" "storage" {
  bucket = aws_s3_bucket.storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "storage" {
  bucket = aws_s3_bucket.storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ECR Repository for Docker images
resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = module.vpc.public_subnets

  enable_deletion_protection = false
  enable_http2              = true

  tags = {
    Name        = "${var.app_name}-alb"
    Environment = var.environment
  }
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.app_name}-alb"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Target Group
resource "aws_lb_target_group" "app" {
  name     = "${var.app_name}-tg-ssl"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/up"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  deregistration_delay = 30

  lifecycle {
    create_before_destroy = true
  }
}

# HTTP Listener (only)
# ACM Certificate
resource "aws_acm_certificate" "main" {
  count = var.create_certificate && var.domain_name != "" ? 1 : 0
  
  domain_name       = var.domain_name
  validation_method = "DNS"

  subject_alternative_names = [
    "*.${var.domain_name}",
    "www.${var.domain_name}",
    "app.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "main" {
  count = var.create_certificate && var.domain_name != "" ? 1 : 0
  
  certificate_arn = aws_acm_certificate.main[0].arn
  
  lifecycle {
    create_before_destroy = true
  }
}

# ALB Listener - HTTP
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ALB Listener - HTTPS (only created when certificate is validated)
resource "aws_lb_listener" "https" {
  count = var.create_certificate && var.domain_name != "" ? 1 : 0
  
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = aws_acm_certificate_validation.main[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  
  depends_on = [aws_acm_certificate_validation.main]
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = var.app_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.ecs_task_cpu
  memory                   = var.ecs_task_memory
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name  = var.app_name
      image = "${aws_ecr_repository.app.repository_url}:latest"
      
      portMappings = [
        {
          containerPort = 3000
          protocol      = "tcp"
        }
      ]
      
      environment = [
        {
          name  = "RAILS_ENV"
          value = "production"
        },
        {
          name  = "RAILS_LOG_TO_STDOUT"
          value = "true"
        },
        {
          name  = "APPLICATION_HOST"
          value = var.domain_name != "" ? "app.${var.domain_name}" : aws_lb.main.dns_name
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "AWS_S3_BUCKET"
          value = aws_s3_bucket.storage.id
        },
        {
          name  = "RAG_BUCKET"
          value = aws_s3_bucket.rag_storage.id
        },
        {
          name  = "AI_PROVIDER"
          value = "bedrock"
        },
        {
          name  = "PORT"
          value = "3000"
        },
        {
          name  = "MAILER_SENDER"
          value = "noreply@${var.mail_from_domain}"
        },
        {
          name  = "SES_CONFIGURATION_SET"
          value = var.app_name
        }
      ]
      
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        },
        {
          name      = "RAILS_MASTER_KEY"
          valueFrom = aws_secretsmanager_secret.rails_master_key.arn
        },
        {
          name      = "REDIS_URL"
          valueFrom = aws_secretsmanager_secret.redis_url.arn
        },
        {
          name      = "PINECONE_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.pinecone_api_key.arn
        },
        {
          name      = "PINECONE_ENVIRONMENT"
          valueFrom = data.aws_secretsmanager_secret.pinecone_environment.arn
        },
        {
          name      = "PINECONE_INDEX_NAME"
          valueFrom = data.aws_secretsmanager_secret.pinecone_index_name.arn
        },
        {
          name      = "OPENAI_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.openai_api_key.arn
        },
        {
          name      = "ANTHROPIC_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.anthropic_api_key.arn
        },
        {
          name      = "ELEVEN_LABS_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.eleven_labs_api_key.arn
        },
        {
          name      = "SERPER_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.serper_api_key.arn
        },
        {
          name      = "STRIPE_SECRET_KEY"
          valueFrom = data.aws_secretsmanager_secret.stripe_secret_key.arn
        },
        {
          name      = "STRIPE_PUBLISHABLE_KEY"
          valueFrom = data.aws_secretsmanager_secret.stripe_publishable_key.arn
        },
        {
          name      = "STRIPE_WEBHOOK_SECRET"
          valueFrom = data.aws_secretsmanager_secret.stripe_webhook_secret.arn
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = "/ecs/${var.app_name}"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
      
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:3000/up || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    },
    {
      name  = "solid-queue-worker"
      image = "${aws_ecr_repository.app.repository_url}:latest"
      command = ["bundle", "exec", "rake", "solid_queue:start"]
      
      environment = [
        {
          name  = "RAILS_ENV"
          value = "production"
        },
        {
          name  = "RAILS_LOG_TO_STDOUT"
          value = "true"
        },
        {
          name  = "AWS_REGION"
          value = var.aws_region
        },
        {
          name  = "AWS_S3_BUCKET"
          value = aws_s3_bucket.storage.id
        },
        {
          name  = "RAG_BUCKET"
          value = aws_s3_bucket.rag_storage.id
        },
        {
          name  = "AI_PROVIDER"
          value = "bedrock"
        },
        {
          name  = "MAILER_SENDER"
          value = "noreply@${var.mail_from_domain}"
        },
        {
          name  = "SES_CONFIGURATION_SET"
          value = var.app_name
        }
      ]
      
      secrets = [
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        },
        {
          name      = "RAILS_MASTER_KEY"
          valueFrom = aws_secretsmanager_secret.rails_master_key.arn
        },
        {
          name      = "REDIS_URL"
          valueFrom = aws_secretsmanager_secret.redis_url.arn
        },
        {
          name      = "PINECONE_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.pinecone_api_key.arn
        },
        {
          name      = "PINECONE_ENVIRONMENT"
          valueFrom = data.aws_secretsmanager_secret.pinecone_environment.arn
        },
        {
          name      = "PINECONE_INDEX_NAME"
          valueFrom = data.aws_secretsmanager_secret.pinecone_index_name.arn
        },
        {
          name      = "OPENAI_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.openai_api_key.arn
        },
        {
          name      = "ANTHROPIC_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.anthropic_api_key.arn
        },
        {
          name      = "ELEVEN_LABS_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.eleven_labs_api_key.arn
        },
        {
          name      = "SERPER_API_KEY"
          valueFrom = data.aws_secretsmanager_secret.serper_api_key.arn
        },
        {
          name      = "STRIPE_SECRET_KEY"
          valueFrom = data.aws_secretsmanager_secret.stripe_secret_key.arn
        },
        {
          name      = "STRIPE_PUBLISHABLE_KEY"
          valueFrom = data.aws_secretsmanager_secret.stripe_publishable_key.arn
        },
        {
          name      = "STRIPE_WEBHOOK_SECRET"
          valueFrom = data.aws_secretsmanager_secret.stripe_webhook_secret.arn
        }
      ]
      
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-create-group"  = "true"
          "awslogs-group"         = "/ecs/${var.app_name}-worker"
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# ECS Service
resource "aws_ecs_service" "app" {
  name            = var.app_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  
  # Give the container more time to start before health checks begin
  health_check_grace_period_seconds = 300
  
  # Enable ECS Execute Command for debugging and maintenance
  enable_execute_command = true

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets          = module.vpc.private_subnets
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = var.app_name
    container_port   = 3000
  }

  depends_on = [
    aws_lb_listener.http
  ]
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "${var.app_name}-ecs-tasks"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM Roles
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.app_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_execution_secrets" {
  name = "${var.app_name}-ecs-execution-secrets"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.database_url.arn,
          aws_secretsmanager_secret.rails_master_key.arn,
          aws_secretsmanager_secret.redis_url.arn,
          data.aws_secretsmanager_secret.pinecone_api_key.arn,
          data.aws_secretsmanager_secret.pinecone_environment.arn,
          data.aws_secretsmanager_secret.pinecone_index_name.arn,
          data.aws_secretsmanager_secret.openai_api_key.arn,
          data.aws_secretsmanager_secret.anthropic_api_key.arn,
          data.aws_secretsmanager_secret.eleven_labs_api_key.arn,
          data.aws_secretsmanager_secret.serper_api_key.arn,
          data.aws_secretsmanager_secret.stripe_secret_key.arn,
          data.aws_secretsmanager_secret.stripe_publishable_key.arn,
          data.aws_secretsmanager_secret.stripe_webhook_secret.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_execution_logs" {
  name = "${var.app_name}-ecs-execution-logs"
  role = aws_iam_role.ecs_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_task_role" {
  name = "${var.app_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Task role policy for S3 access (Active Storage + RAG Storage)
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.app_name}-ecs-task-s3"
  role = aws_iam_role.ecs_task_role.id

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
          aws_s3_bucket.storage.arn,
          "${aws_s3_bucket.storage.arn}/*",
          aws_s3_bucket.rag_storage.arn,
          "${aws_s3_bucket.rag_storage.arn}/*",
          # Also include the bucket name used by the app (without account ID suffix)
          "arn:aws:s3:::${var.app_name}-rag-storage",
          "arn:aws:s3:::${var.app_name}-rag-storage/*"
        ]
      }
    ]
  })
}

# IAM policy for ECS Execute Command (SSM)
resource "aws_iam_role_policy" "ecs_task_ssm" {
  name = "${var.app_name}-ecs-task-ssm"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

# Task role policy for Bedrock access
resource "aws_iam_role_policy" "ecs_task_bedrock" {
  name = "${var.app_name}-ecs-task-bedrock"
  role = aws_iam_role.ecs_task_role.id

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
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*"
        ]
      }
    ]
  })
}

# ElastiCache subnet group
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.app_name}-redis-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "${var.app_name}-redis-subnet-group"
  }
}

# Security group for ElastiCache
resource "aws_security_group" "redis" {
  name        = "${var.app_name}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
    description     = "Allow Redis access from ECS tasks"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-redis-sg"
  }
}

# ElastiCache Redis cluster
resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.app_name}-redis"
  engine               = "redis"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  engine_version       = "7.0"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = {
    Name = "${var.app_name}-redis"
  }
}

# Secrets Manager
resource "aws_secretsmanager_secret" "database_url" {
  name = "${var.app_name}-database-url"
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id = aws_secretsmanager_secret.database_url.id
  secret_string = "postgresql://${aws_db_instance.postgres.username}:${random_password.db_password.result}@${aws_db_instance.postgres.endpoint}/${aws_db_instance.postgres.db_name}"
}

resource "aws_secretsmanager_secret" "rails_master_key" {
  name = "${var.app_name}-rails-master-key"
}

resource "aws_secretsmanager_secret" "redis_url" {
  name = "${var.app_name}-redis-url"
}

resource "aws_secretsmanager_secret_version" "redis_url" {
  secret_id = aws_secretsmanager_secret.redis_url.id
  secret_string = "redis://${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}

# Data sources
data "aws_caller_identity" "current" {}

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

data "aws_secretsmanager_secret" "stripe_secret_key" {
  name = "${var.app_name}-stripe-secret-key"
}

data "aws_secretsmanager_secret" "stripe_publishable_key" {
  name = "${var.app_name}-stripe-publishable-key"
}

data "aws_secretsmanager_secret" "stripe_webhook_secret" {
  name = "${var.app_name}-stripe-webhook-secret"
}

# VPC Endpoints for private subnet access to AWS services
resource "aws_vpc_endpoint" "secrets_manager" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "${var.app_name}-secrets-manager-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "${var.app_name}-ecr-dkr-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "${var.app_name}-ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "${var.app_name}-logs-endpoint"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.private_route_table_ids
  
  tags = {
    Name = "${var.app_name}-s3-endpoint"
  }
}

# SES VPC Endpoint - Required for sending emails from private subnets without NAT Gateway
resource "aws_vpc_endpoint" "ses" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.email"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnets
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  
  private_dns_enabled = true
  
  tags = {
    Name = "${var.app_name}-ses-endpoint"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.app_name}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.app_name}-vpc-endpoints"
  }
}

# Outputs
output "alb_dns_name" {
  value       = aws_lb.main.dns_name
  description = "DNS name of the load balancer - use this to access your app"
}

output "ecr_repository_url" {
  value       = aws_ecr_repository.app.repository_url
  description = "URL of the ECR repository"
}

output "database_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "RDS database endpoint"
}

output "certificate_arn" {
  value       = var.create_certificate && var.domain_name != "" ? aws_acm_certificate.main[0].arn : ""
  description = "ARN of the ACM certificate"
}

output "certificate_validation_records" {
  value = var.create_certificate && var.domain_name != "" ? {
    for dvo in aws_acm_certificate.main[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  } : {}
  description = "DNS records required for certificate validation"
}

output "redis_endpoint" {
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  description = "Redis cluster endpoint"
}

output "setup_instructions" {
  value = <<EOF
🎉 AWS Infrastructure Created Successfully!

Next steps:

1. Store your Rails master key:
   aws secretsmanager put-secret-value \
     --secret-id "${aws_secretsmanager_secret.rails_master_key.name}" \
     --secret-string "$(cat config/master.key)" \
     --region ${var.aws_region}

2. Build and deploy your application:
   ./aws/deploy.sh

3. Access your application:
   http://${aws_lb.main.dns_name}

Note: For production use with a custom domain, you'll need to:
- Set up an SSL certificate manually
- Configure your DNS to point to the load balancer
EOF
  description = "Setup instructions"
}
