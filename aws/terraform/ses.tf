resource "aws_ses_domain_identity" "main" {
  count  = var.domain_name != "" ? 1 : 0
  domain = var.domain_name
}

resource "aws_ses_domain_dkim" "main" {
  count  = var.domain_name != "" ? 1 : 0
  domain = aws_ses_domain_identity.main[0].domain
}

resource "aws_iam_role_policy" "ecs_task_ses" {
  name = "${var.app_name}-ecs-task-ses"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail",
          "ses:GetSendQuota",
          "ses:GetSendStatistics"
        ]
        Resource = "*"
      }
    ]
  })
}

output "ses_domain_verification_token" {
  value = var.domain_name != "" ? aws_ses_domain_identity.main[0].verification_token : ""
}

output "ses_dkim_tokens" {
  value = var.domain_name != "" ? aws_ses_domain_dkim.main[0].dkim_tokens : []
}

