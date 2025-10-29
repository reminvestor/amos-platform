#!/bin/bash

echo "Enabling pgvector on RDS instances..."

# Function to enable pgvector on an RDS instance
enable_pgvector() {
    local db_identifier=$1
    local db_endpoint=$2
    local db_name=$3
    
    echo "Enabling pgvector on $db_identifier..."
    
    # Get the master password from secrets manager
    if [[ $db_identifier == *"dev"* ]]; then
        SECRET_ID="agent-marketing-dev-database-url"
    else
        SECRET_ID="agent-marketing-database-url"
    fi
    
    # Extract password from database URL
    DB_URL=$(aws secretsmanager get-secret-value --secret-id $SECRET_ID --query SecretString --output text)
    DB_PASSWORD=$(echo $DB_URL | sed -n 's/.*postgres:\([^@]*\)@.*/\1/p' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))")
    
    echo "Connecting to $db_endpoint..."
    
    # Create the extension
    PGPASSWORD=$DB_PASSWORD psql -h $db_endpoint -U postgres -d $db_name -c "CREATE EXTENSION IF NOT EXISTS vector;"
    
    if [ $? -eq 0 ]; then
        echo "✅ pgvector enabled on $db_identifier"
    else
        echo "❌ Failed to enable pgvector on $db_identifier"
        echo "You may need to:"
        echo "1. Add pgvector to the RDS parameter group"
        echo "2. Ensure the RDS instance supports pgvector (PostgreSQL 11+)"
    fi
}

# Check if psql is installed
if ! command -v psql &> /dev/null; then
    echo "❌ psql command not found. Please install PostgreSQL client tools:"
    echo "   brew install postgresql"
    exit 1
fi

# Production RDS
echo "=== PRODUCTION RDS ==="
PROD_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier agent-marketing-db --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null)
if [ ! -z "$PROD_ENDPOINT" ]; then
    enable_pgvector "agent-marketing-db" "$PROD_ENDPOINT" "agent_marketing_production"
else
    echo "⚠️  Production RDS not found"
fi

echo ""

# Dev RDS
echo "=== DEV RDS ==="
DEV_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier agent-marketing-dev-db --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null)
if [ ! -z "$DEV_ENDPOINT" ]; then
    enable_pgvector "agent-marketing-dev-db" "$DEV_ENDPOINT" "agent_marketing_production"  # Note: using production DB name since we copied from prod
else
    echo "⚠️  Dev RDS not found"
fi

echo ""
echo "Done!"
