# RDS PostgreSQL with pgvector Extension
# This file configures the database to support vector similarity search for the RAG system

# Custom parameter group with pgvector enabled
resource "aws_db_parameter_group" "postgres_with_pgvector" {
  name        = "${var.app_name}-postgres-pgvector-v3"  # Changed name again to force new resource
  family      = "postgres15"
  description = "PostgreSQL parameter group optimized for RAG system"

  # Note: pgvector is included natively in RDS PostgreSQL 15.2+ 
  # No need to add to shared_preload_libraries
  # Just CREATE EXTENSION vector; in the database
  
  lifecycle {
    create_before_destroy = true
  }

  # Only include dynamic parameters that don't require restart
  parameter {
    name  = "random_page_cost"
    value = "1.1" # Lower for SSD storage
  }

  parameter {
    name  = "work_mem"
    value = "16384" # 16MB for sorting/hashing operations
  }

  tags = {
    Name        = "${var.app_name}-postgres-pgvector"
    Environment = var.environment
    Purpose     = "RAG vector similarity search"
  }
}

# Note: The main RDS instance is defined in main.tf (lines 113-141)
# To enable pgvector, update the aws_db_instance.postgres resource in main.tf:
#
# Add this line to the resource block:
#   parameter_group_name = aws_db_parameter_group.postgres_with_pgvector.name
#
# This will require a database restart during the next apply.
# Consider upgrading instance class to db.t3.small or larger for RAG workload.

# Output parameter group name for reference
output "postgres_parameter_group" {
  value       = aws_db_parameter_group.postgres_with_pgvector.name
  description = "PostgreSQL parameter group with pgvector enabled"
}
