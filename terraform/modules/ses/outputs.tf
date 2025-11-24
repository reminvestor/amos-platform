output "ses_domain_identity_arn" {
  value = aws_ses_domain_identity.main.arn
}

output "ses_verification_token" {
  value = aws_ses_domain_identity.main.verification_token
  description = "TXT record value for domain verification. Host: _amazonses.example.com"
}

output "dkim_tokens" {
  value = aws_ses_domain_dkim.main.dkim_tokens
  description = "CNAME record values for DKIM verification. Hosts: token._domainkey.example.com"
}

