# Backend configuration for Terraform state
terraform {
  backend "s3" {
    # Backend configuration will be provided via -backend-config during init
  }
}
