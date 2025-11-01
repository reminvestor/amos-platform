# terraform/environments/production.tfvars
# Production environment configuration

environment = "production"
aws_region  = "us-east-1"

# VPC Configuration - Multi-AZ for high availability
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets    = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

# Database Configuration - Production grade
db_instance_class    = "db.t3.xlarge"
db_allocated_storage = 500
db_engine_version    = "15.4"

# Cost Management
monthly_budget_amount = 5000
alert_email_addresses = [
  "ops-team@example.com",
  "finance@example.com",
  "engineering-leads@example.com"
]

# Lambda Configuration
lambda_memory_size = 2048
lambda_timeout     = 900

# Auto Scaling - Production capacity
min_capacity           = 3
max_capacity           = 20
target_cpu_utilization = 60

# Security - Restricted access
allowed_ip_ranges = [
  "52.23.45.0/24",    # Office IP range
  "10.0.0.0/16"       # VPC internal
]
enable_deletion_protection = true

# Backup Configuration
backup_retention_days = 30
backup_window         = "03:00-04:00"
maintenance_window    = "sun:04:00-sun:05:00"

# Monitoring - Full monitoring
enable_enhanced_monitoring = true
alarm_notification_enabled = true

# CloudWatch
log_retention_days = 90

# Tags
additional_tags = {
  Team           = "Production"
  CostCenter     = "Operations"
  Compliance     = "SOC2"
  DataClass      = "Confidential"
  BackupPolicy   = "Daily"
  DisasterRecovery = "Required"
}