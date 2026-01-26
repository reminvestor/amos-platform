# ═══════════════════════════════════════════════════════════════════════════
# CodeBuild Test Project
# Runs all tests before deploying to production
# ═══════════════════════════════════════════════════════════════════════════

resource "aws_codebuild_project" "test" {
  name          = "${var.app_name}-test"
  description   = "Run test suite before deployment"
  service_role  = aws_iam_role.codebuild_test.arn
  build_timeout = 30  # 30 minutes max for tests

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"  # More power for tests
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = false

    environment_variable {
      name  = "RAILS_ENV"
      value = "test"
    }

    environment_variable {
      name  = "AWS_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "PARALLEL_WORKERS"
      value = "1"
    }

    # Database connection for tests (uses separate test RDS or local SQLite)
    environment_variable {
      name  = "DATABASE_URL"
      value = "sqlite3:db/test.sqlite3"  # Use SQLite for CI speed
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec-test.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/${var.app_name}-test"
      stream_name = "test-logs"
    }
  }

  tags = {
    Name        = "${var.app_name}-test"
    Environment = "test"
    Purpose     = "CI/CD Test Stage"
  }
}

# IAM role for test CodeBuild
resource "aws_iam_role" "codebuild_test" {
  name = "${var.app_name}-codebuild-test-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_test" {
  name = "${var.app_name}-codebuild-test-policy"
  role = aws_iam_role.codebuild_test.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.codepipeline_artifacts.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup",
          "codebuild:CreateReport",
          "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases",
          "codebuild:BatchPutCodeCoverages"
        ]
        Resource = "arn:aws:codebuild:${var.aws_region}:${data.aws_caller_identity.current.account_id}:report-group/${var.app_name}-test-*"
      }
    ]
  })
}

# CloudWatch Log Group for test logs
resource "aws_cloudwatch_log_group" "codebuild_test" {
  name              = "/aws/codebuild/${var.app_name}-test"
  retention_in_days = 14  # Keep test logs for 2 weeks
}
