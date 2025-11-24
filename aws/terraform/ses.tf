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

# SES Configuration Set for tracking
resource "aws_ses_configuration_set" "main" {
  name = var.app_name
}

# SNS Topic for SES events
resource "aws_sns_topic" "ses_events" {
  name = "${var.app_name}-ses-events"
}

# Allow SES to publish to this topic
resource "aws_sns_topic_policy" "ses_events" {
  arn = aws_sns_topic.ses_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSESPublish"
        Effect    = "Allow"
        Principal = {
          Service = "ses.amazonaws.com"
        }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.ses_events.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Configure SES to send events to SNS
resource "aws_ses_event_destination" "sns" {
  name                   = "sns-destination"
  configuration_set_name = aws_ses_configuration_set.main.name
  enabled                = true
  matching_types         = ["send", "renderingFailure", "reject", "delivery", "bounce", "complaint", "open", "click"]

  sns_destination {
    topic_arn = aws_sns_topic.ses_events.arn
  }
}

# Subscribe the app endpoint to the SNS topic
# Note: This requires the app to be running and accessible to confirm subscription
resource "aws_sns_topic_subscription" "app_webhook" {
  count     = var.domain_name != "" ? 1 : 0
  topic_arn = aws_sns_topic.ses_events.arn
  protocol  = "https"
  endpoint  = "https://app.${var.domain_name}/webhooks/ses"
  
  # Automatically confirm subscription if possible
  confirmation_timeout_in_minutes = 1
}

output "ses_domain_verification_token" {
  value = var.domain_name != "" ? aws_ses_domain_identity.main[0].verification_token : ""
}

output "ses_dkim_tokens" {
  value = var.domain_name != "" ? aws_ses_domain_dkim.main[0].dkim_tokens : []
}
