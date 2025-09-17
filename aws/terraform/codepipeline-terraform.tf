# CodeBuild project for Terraform
resource "aws_codebuild_project" "terraform" {
  name          = "${var.app_name}-terraform"
  service_role  = aws_iam_role.codebuild_terraform.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                      = "hashicorp/terraform:1.5"
    type                       = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode            = false
  }

  source {
    type = "CODEPIPELINE"
    buildspec = "aws/terraform/buildspec-terraform.yml"
  }
}

# IAM role for Terraform CodeBuild
resource "aws_iam_role" "codebuild_terraform" {
  name = "${var.app_name}-codebuild-terraform-role"

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

resource "aws_iam_role_policy" "codebuild_terraform" {
  name = "${var.app_name}-codebuild-terraform-policy"
  role = aws_iam_role.codebuild_terraform.id

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
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.codepipeline_artifacts.arn
      },
      {
        Effect = "Allow"
        Action = "*"
        Resource = "*"
      }
    ]
  })
}
