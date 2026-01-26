# Landing Page Subdomain Infrastructure
# Enables landing pages to be served from unique subdomains like mypage.lp.amoslabs.com
#
# This file creates:
# - ACM wildcard certificate for *.lp.{domain}
# - Route53 wildcard DNS record pointing to ALB
# - Attaches certificate to existing HTTPS listener

# =============================================================================
# VARIABLES
# =============================================================================

variable "enable_landing_page_subdomains" {
  description = "Enable landing page subdomain support (requires Route53 hosted zone)"
  type        = bool
  default     = true
}

variable "route53_zone_id" {
  description = "Route53 hosted zone ID for the domain (leave empty to look up by domain name)"
  type        = string
  default     = ""
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Look up the Route53 hosted zone for the domain
# Only if use_route53 is enabled (skipped when using external DNS like GoDaddy)
data "aws_route53_zone" "main" {
  count = var.enable_landing_page_subdomains && var.domain_name != "" && var.use_route53 ? 1 : 0

  name         = var.domain_name
  private_zone = false
}

# Get the hosted zone ID - either from variable or data source lookup
locals {
  route53_zone_id = var.route53_zone_id != "" ? var.route53_zone_id : (
    length(data.aws_route53_zone.main) > 0 ? data.aws_route53_zone.main[0].zone_id : ""
  )
}

# =============================================================================
# ACM CERTIFICATE FOR LANDING PAGE SUBDOMAINS
# =============================================================================

# Wildcard certificate for *.lp.{domain}
resource "aws_acm_certificate" "landing_pages" {
  count = var.enable_landing_page_subdomains && var.create_certificate && var.domain_name != "" ? 1 : 0

  domain_name       = "lp.${var.domain_name}"
  validation_method = "DNS"

  subject_alternative_names = [
    "*.lp.${var.domain_name}"
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.app_name}-landing-pages-cert"
    Environment = var.environment
    Purpose     = "Landing page subdomain SSL"
  }
}

# DNS validation records for the certificate
resource "aws_route53_record" "landing_pages_cert_validation" {
  for_each = var.enable_landing_page_subdomains && var.create_certificate && var.domain_name != "" && local.route53_zone_id != "" ? {
    for dvo in aws_acm_certificate.landing_pages[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = local.route53_zone_id
}

# Certificate validation
resource "aws_acm_certificate_validation" "landing_pages" {
  count = var.enable_landing_page_subdomains && var.create_certificate && var.domain_name != "" && local.route53_zone_id != "" ? 1 : 0

  certificate_arn         = aws_acm_certificate.landing_pages[0].arn
  validation_record_fqdns = [for record in aws_route53_record.landing_pages_cert_validation : record.fqdn]

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# ROUTE53 DNS RECORDS
# =============================================================================

# Wildcard A record for *.lp.{domain} pointing to ALB
resource "aws_route53_record" "landing_pages_wildcard" {
  count = var.enable_landing_page_subdomains && var.domain_name != "" && local.route53_zone_id != "" ? 1 : 0

  zone_id = local.route53_zone_id
  name    = "*.lp.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# Base record for lp.{domain} (for potential landing pages index or 404 page)
resource "aws_route53_record" "landing_pages_base" {
  count = var.enable_landing_page_subdomains && var.domain_name != "" && local.route53_zone_id != "" ? 1 : 0

  zone_id = local.route53_zone_id
  name    = "lp.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# =============================================================================
# ALB LISTENER CERTIFICATE
# =============================================================================

# Attach the landing pages certificate to the existing HTTPS listener
# This allows the ALB to serve HTTPS traffic for *.lp.{domain}
resource "aws_lb_listener_certificate" "landing_pages" {
  count = var.enable_landing_page_subdomains && var.create_certificate && var.domain_name != "" && local.route53_zone_id != "" ? 1 : 0

  listener_arn    = aws_lb_listener.https[0].arn
  certificate_arn = aws_acm_certificate_validation.landing_pages[0].certificate_arn

  depends_on = [aws_acm_certificate_validation.landing_pages]
}

# =============================================================================
# OUTPUTS
# =============================================================================

output "landing_pages_certificate_arn" {
  description = "ARN of the landing pages wildcard certificate"
  value       = var.enable_landing_page_subdomains && length(aws_acm_certificate.landing_pages) > 0 ? aws_acm_certificate.landing_pages[0].arn : null
}

output "landing_pages_base_url" {
  description = "Base URL for landing page subdomains"
  value       = var.enable_landing_page_subdomains && var.domain_name != "" ? "https://{subdomain}.lp.${var.domain_name}" : null
}

output "landing_pages_dns_records" {
  description = "DNS records created for landing pages"
  value = var.enable_landing_page_subdomains && var.domain_name != "" ? {
    wildcard = "*.lp.${var.domain_name}"
    base     = "lp.${var.domain_name}"
  } : null
}

# Instructions for external DNS (GoDaddy, etc.)
output "external_dns_instructions" {
  description = "DNS records to create manually if using external DNS (GoDaddy, Cloudflare, etc.)"
  value = !var.use_route53 && var.domain_name != "" ? {
    message = "Create these DNS records in your DNS provider (GoDaddy):"
    records = [
      {
        type  = "CNAME"
        name  = "app.${var.domain_name}"
        value = "${var.app_name}-alb.${var.aws_region}.elb.amazonaws.com"
        note  = "Points app subdomain to your ALB"
      },
      {
        type  = "CNAME" 
        name  = "www.${var.domain_name}"
        value = "app.${var.domain_name}"
        note  = "Redirect www to app"
      }
    ]
    ssl_validation = "For SSL certificates, add the CNAME records shown in AWS Certificate Manager console"
  } : null
}
