#!/bin/bash

# Import existing dev secrets into Terraform state
# This prevents "already exists" errors

echo "Importing existing dev secrets..."

# Rails master key
terraform import aws_secretsmanager_secret.rails_master_key "agent-marketing-dev-rails-master-key" || echo "Rails master key already imported"

# Database URL  
terraform import aws_secretsmanager_secret.database_url "agent-marketing-dev-database-url" || echo "Database URL already imported"

# Redis URL
terraform import aws_secretsmanager_secret.redis_url "agent-marketing-dev-redis-url" || echo "Redis URL already imported"

echo "Import complete!"
