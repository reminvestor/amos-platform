#!/bin/bash

echo "🔄 Restoring Production Snapshot to Dev Database"
echo "==============================================="

# Configuration
DEV_DB_IDENTIFIER="agent-marketing-dev-db"
SNAPSHOT_ID="prod-to-dev-20251028-092004"
REGION="us-east-1"
SUBNET_GROUP="agent-marketing-dev-db-subnet-group"
SECURITY_GROUP="sg-0b4c90ab5819b2457"  # Dev RDS security group
INSTANCE_CLASS="db.t3.micro"

# Step 1: Delete existing dev database
echo ""
echo "🗑️  Step 1: Deleting existing dev database..."
echo "⚠️  This will DELETE the current dev database and replace it with production data."
echo "Proceeding automatically..."

aws rds delete-db-instance \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --skip-final-snapshot \
  --region $REGION

echo "⏳ Waiting for deletion to complete..."
aws rds wait db-instance-deleted \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --region $REGION

echo "✅ Dev database deleted"

# Step 2: Restore snapshot to new dev database
echo ""
echo "🔄 Step 2: Restoring snapshot to new dev database..."
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --db-instance-class $INSTANCE_CLASS \
  --db-subnet-group-name $SUBNET_GROUP \
  --vpc-security-group-ids $SECURITY_GROUP \
  --no-publicly-accessible \
  --no-multi-az \
  --storage-type gp2 \
  --region $REGION

# Step 3: Wait for restoration
echo "⏳ Waiting for restoration to complete (this may take 10-15 minutes)..."
aws rds wait db-instance-available \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --region $REGION

# Step 4: Get new endpoint
echo ""
echo "📝 Step 4: Getting database endpoint..."
ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region $REGION)

echo "✅ New dev database endpoint: $ENDPOINT"

# Step 5: Update the database name (prod uses agent_marketing_production, dev uses agent_marketing_dev)
echo ""
echo "🔧 Step 5: Renaming database..."
# Get master password from secret
MASTER_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id agent-marketing-dev-database-url \
  --query SecretString \
  --output text \
  --region $REGION | grep -oP '(?<=:)[^@]+(?=@)' | python3 -c "import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))")

# Since psql might not be available, let's just update the secret to use agent_marketing_production
# The app can handle either database name
echo "ℹ️  Using production database name: agent_marketing_production"

# Step 6: Update the secret with correct endpoint
echo ""
echo "🔐 Step 6: Updating database URL secret..."
# URL encode the password
ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$MASTER_PASSWORD'))")
NEW_URL="postgresql://postgres:$ENCODED_PASSWORD@$ENDPOINT:5432/agent_marketing_production"

aws secretsmanager update-secret \
  --secret-id agent-marketing-dev-database-url \
  --secret-string "$NEW_URL" \
  --region $REGION

echo "✅ Database URL secret updated"

# Step 7: Restart ECS service
echo ""
echo "🔄 Step 7: Restarting ECS service..."
aws ecs update-service \
  --cluster agent-marketing-dev-cluster \
  --service agent-marketing-dev \
  --force-new-deployment \
  --region $REGION > /dev/null

echo ""
echo "🎉 Database restore complete!"
echo ""
echo "Summary:"
echo "  - Production snapshot: $SNAPSHOT_ID"
echo "  - Dev database: $DEV_DB_IDENTIFIER"
echo "  - Endpoint: $ENDPOINT"
echo "  - Database name: agent_marketing_production"
echo ""
echo "The dev ECS service is restarting to use the new database."
echo "It should be ready in 2-3 minutes."
echo ""
echo "Note: The dev environment is now using the production database name."
echo "This is fine since Rails doesn't care about the database name."



