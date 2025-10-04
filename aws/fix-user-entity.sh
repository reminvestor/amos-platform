#!/bin/bash
# Script to fix user-entity relationships in production via Rails runner

echo "🔧 Fixing user-entity relationships in production..."

# Get the task ARN for the running web container
TASK_ARN=$(aws ecs list-tasks \
  --cluster agent-marketing-cluster \
  --service-name agent-marketing \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text \
  --region us-east-1)

if [ -z "$TASK_ARN" ] || [ "$TASK_ARN" == "None" ]; then
  echo "❌ No running tasks found"
  exit 1
fi

echo "📦 Found running task"

# Execute simple one-liner to fix user-entity links
echo "🚀 Running fix script..."
echo ""

aws ecs execute-command \
  --cluster agent-marketing-cluster \
  --task "${TASK_ARN}" \
  --container agent-marketing \
  --command "/bin/sh -c 'cd /rails && bin/rails runner \"User.find_each { |u| eu = u.entity_users.first; u.update_column(:entity_id, eu.entity_id) if eu && u.entity_id.nil? }; puts User.where.not(entity_id: nil).count.to_s + \\\" users linked\\\"\"'" \
  --interactive \
  --region us-east-1

echo ""
echo "✅ User-entity relationships fixed!"

