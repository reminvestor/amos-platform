# Dev Environment Configuration

# Basic settings
aws_region  = "us-east-1"
environment = "dev"
app_name    = "agent-marketing-dev"
domain_name = "dev.amoslabs.com"

# DNS is managed in GoDaddy, not Route 53
# Route 53 resources will be skipped - DNS records must be created manually in GoDaddy
use_route53 = false

# GitHub settings
github_owner  = "NuvolaNetworks"
github_repo   = "agent_marketing"
github_branch = "dev"

# Smaller instance sizes for dev
ecs_task_cpu    = "1024"  # 1 vCPU (prod uses 2048)
ecs_task_memory = "2048"  # 2 GB (prod uses 4096)

# Smaller RDS for dev
db_instance_class = "db.t3.micro"  # Cheaper than prod
db_allocated_storage = 20  # 20 GB vs prod's larger size
db_backup_retention_period = 1  # 1 day vs prod's 7 days

# Smaller Redis for dev  
redis_node_type = "cache.t3.micro"  # Cheaper than prod

# Dev-specific settings
enable_deletion_protection = false  # Allow easy cleanup
skip_final_snapshot = true  # Don't need snapshots in dev
multi_az = false  # Single AZ for dev (cheaper)

# Cost optimization - Skip SSL cert for dev (use ALB DNS directly)
create_certificate = false

# Disable landing page subdomains for dev (requires Route53 hosted zone)
enable_landing_page_subdomains = false

# Skip NAT gateways to avoid EIP limit (dev can use public subnets)
enable_nat_gateway = false
single_nat_gateway = false

# Auto-scaling (lighter for dev)
ecs_desired_count = 1
ecs_min_count = 1
ecs_max_count = 2  # Max 2 tasks in dev vs more in prod

