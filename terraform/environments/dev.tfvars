# terraform/environments/dev.tfvars
# Development environment configuration

environment = "dev"
aws_region  = "us-east-1"

# VPC Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
public_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets    = ["10.0.11.0/24", "10.0.12.0/24"]

# Database Configuration
db_instance_class    = "db.t3.small"
db_allocated_storage = 50
db_engine_version    = "15.4"

# Cost Management
monthly_budget_amount = 500
alert_email_addresses = [
  "dev-team@example.com"
]

# Lambda Configuration
lambda_memory_size = 512
lambda_timeout     = 300

# Auto Scaling
min_capacity           = 1
max_capacity           = 3
target_cpu_utilization = 70

# Security
allowed_ip_ranges          = ["0.0.0.0/0"]  # Open for dev
enable_deletion_protection = false

# Backup Configuration
backup_retention_days = 3
backup_window         = "03:00-04:00"
maintenance_window    = "sun:04:00-sun:05:00"

# Monitoring
enable_enhanced_monitoring = false
alarm_notification_enabled = true

# CloudWatch
log_retention_days = 7

# Tags
additional_tags = {
  Team        = "Development"
  CostCenter  = "Engineering"
  AutoShutdown = "true"
}