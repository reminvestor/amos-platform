resource "aws_ses_domain_identity" "main" {
  domain = var.domain_name
}

resource "aws_ses_domain_dkim" "main" {
  domain = aws_ses_domain_identity.main.domain
}

# Optional: Create an email identity for a specific address (e.g. noreply@...)
# This is useful for testing or if domain verification takes time
resource "aws_ses_email_identity" "noreply" {
  email = "noreply@${var.domain_name}"
}

