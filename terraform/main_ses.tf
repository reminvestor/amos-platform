# SES Configuration
module "ses" {
  source = "./modules/ses"

  project_name = var.project_name
  environment  = var.environment
  domain_name  = var.domain_name
}

