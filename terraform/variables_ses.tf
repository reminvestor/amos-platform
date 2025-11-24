# SES Configuration
variable "domain_name" {
  description = "Domain name for SES"
  type        = string
  default     = "amoslabs.com"
}

variable "notification_email" {
  description = "Email address for SES notifications/verification"
  type        = string
  default     = ""
}

