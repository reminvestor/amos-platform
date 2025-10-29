#!/bin/bash

echo "🔄 Copying Production Database to Dev Environment"
echo "================================================"

# Configuration
PROD_DB_IDENTIFIER="agent-marketing-db"
DEV_DB_IDENTIFIER="agent-marketing-dev-db"
SNAPSHOT_ID="prod-to-dev-$(date +%Y%m%d-%H%M%S)"
REGION="us-east-1"

# Step 1: Create snapshot of production database
echo ""
echo "📸 Step 1: Creating snapshot of production database..."
aws rds create-db-snapshot \
  --db-instance-identifier $PROD_DB_IDENTIFIER \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region $REGION

echo "⏳ Waiting for snapshot to complete (this may take 5-10 minutes)..."
aws rds wait db-snapshot-completed \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --region $REGION

echo "✅ Snapshot created: $SNAPSHOT_ID"

# Step 2: Get current dev database configuration
echo ""
echo "📋 Step 2: Getting dev database configuration..."
DEV_DB_INFO=$(aws rds describe-db-instances \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --region $REGION \
  --query 'DBInstances[0].[DBSubnetGroupName,VpcSecurityGroups[0].VpcSecurityGroupId,DBInstanceClass,AllocatedStorage]' \
  --output text)

SUBNET_GROUP=$(echo $DEV_DB_INFO | cut -d' ' -f1)
SECURITY_GROUP=$(echo $DEV_DB_INFO | cut -d' ' -f2)
INSTANCE_CLASS=$(echo $DEV_DB_INFO | cut -d' ' -f3)
STORAGE=$(echo $DEV_DB_INFO | cut -d' ' -f4)

# Handle case where subnet group shows as "None"
if [ "$SUBNET_GROUP" == "None" ]; then
  SUBNET_GROUP="agent-marketing-dev-db-subnet-group"
fi

echo "Dev DB Config:"
echo "  Subnet Group: $SUBNET_GROUP"
echo "  Security Group: $SECURITY_GROUP"
echo "  Instance Class: $INSTANCE_CLASS"
echo "  Storage: ${STORAGE}GB"

# Step 3: Delete existing dev database
echo ""
echo "🗑️  Step 3: Deleting existing dev database..."
read -p "⚠️  This will DELETE the current dev database. Continue? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  aws rds delete-db-instance \
    --db-instance-identifier $DEV_DB_IDENTIFIER \
    --skip-final-snapshot \
    --region $REGION
  
  echo "⏳ Waiting for deletion to complete..."
  aws rds wait db-instance-deleted \
    --db-instance-identifier $DEV_DB_IDENTIFIER \
    --region $REGION
  
  echo "✅ Dev database deleted"
else
  echo "❌ Cancelled"
  exit 1
fi

# Step 4: Restore snapshot to new dev database
echo ""
echo "🔄 Step 4: Restoring snapshot to new dev database..."
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --db-instance-class $INSTANCE_CLASS \
  --db-subnet-group-name $SUBNET_GROUP \
  --no-publicly-accessible \
  --region $REGION

# Step 5: Wait for restoration
echo "⏳ Waiting for restoration to complete (this may take 10-15 minutes)..."
aws rds wait db-instance-available \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --region $REGION

# Step 6: Apply security group
echo ""
echo "🔒 Step 6: Applying security group..."
aws rds modify-db-instance \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --vpc-security-group-ids $SECURITY_GROUP \
  --apply-immediately \
  --region $REGION

# Step 7: Update database name if needed
echo ""
echo "📝 Step 7: Getting database endpoint..."
ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier $DEV_DB_IDENTIFIER \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region $REGION)

echo "✅ New dev database endpoint: $ENDPOINT"

# Step 8: Update the secret with new endpoint
echo ""
echo "🔐 Step 8: Updating database URL secret..."
# Get the current secret value
CURRENT_SECRET=$(aws secretsmanager get-secret-value \
  --secret-id agent-marketing-dev-database-url \
  --query SecretString \
  --output text \
  --region $REGION)

# Parse the URL and update with new endpoint
if [[ $CURRENT_SECRET =~ postgresql://([^:]+):([^@]+)@([^/]+)/(.+) ]]; then
  USERNAME="${BASH_REMATCH[1]}"
  PASSWORD="${BASH_REMATCH[2]}"
  OLD_HOST="${BASH_REMATCH[3]}"
  DATABASE="${BASH_REMATCH[4]}"
  
  # URL encode the password
  ENCODED_PASSWORD=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$PASSWORD'))")
  
  NEW_URL="postgresql://$USERNAME:$ENCODED_PASSWORD@$ENDPOINT:5432/agent_marketing_dev"
  
  aws secretsmanager update-secret \
    --secret-id agent-marketing-dev-database-url \
    --secret-string "$NEW_URL" \
    --region $REGION
  
  echo "✅ Database URL secret updated"
else
  echo "⚠️  Could not parse database URL. You may need to update it manually."
fi

# Step 9: Restart ECS service
echo ""
echo "🔄 Step 9: Restarting ECS service..."
aws ecs update-service \
  --cluster agent-marketing-dev-cluster \
  --service agent-marketing-dev \
  --force-new-deployment \
  --region $REGION > /dev/null

echo ""
echo "🎉 Database copy complete!"
echo ""
echo "Summary:"
echo "  - Production snapshot: $SNAPSHOT_ID"
echo "  - Dev database: $DEV_DB_IDENTIFIER"
echo "  - Endpoint: $ENDPOINT"
echo ""
echo "The dev ECS service is restarting to use the new database."
echo "It should be ready in 2-3 minutes."
echo ""
echo "⚠️  Note: Remember to sanitize any sensitive production data if needed!"
