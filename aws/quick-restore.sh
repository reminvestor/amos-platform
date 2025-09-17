#!/bin/bash

# Quick restore - no deployment needed!
# Just runs psql directly on the ECS container

echo "🚀 Quick database restore (no deployment required)"

# First, make sure the SQL file is in S3
if [ -f /tmp/restore.sql ]; then
    echo "Uploading SQL to S3..."
    aws s3 cp /tmp/restore.sql s3://agent-marketing-storage-637423327454/db-restore/restore.sql
else
    echo "SQL file already in S3"
fi

# Get task ARN
TASK_ARN=$(aws ecs list-tasks --cluster agent-marketing-cluster --service-name agent-marketing --query 'taskArns[0]' --output text)

echo "Running restore directly on ECS container..."
echo "This will take a few minutes..."

# Run the restore in one command
aws ecs execute-command \
  --cluster agent-marketing-cluster \
  --task $TASK_ARN \
  --container agent-marketing \
  --interactive \
  --command "/bin/bash -c '
    cd /rails && 
    echo \"Downloading SQL from S3 using Ruby...\" &&
    bundle exec rails runner \"
      require \\\"aws-sdk-s3\\\"
      s3 = Aws::S3::Client.new(region: \\\"us-east-1\\\")
      puts \\\"Downloading restore.sql from S3...\\\"
      s3.get_object(
        bucket: \\\"agent-marketing-storage-637423327454\\\",
        key: \\\"db-restore/restore.sql\\\",
        response_target: \\\"/tmp/restore.sql\\\"
      )
      puts \\\"Downloaded: #{File.size(\\\"/tmp/restore.sql\\\") / 1024 / 1024} MB\\\"
    \" &&
    echo \"Running psql restore...\" &&
    export PGPASSWORD=\$(echo \$DATABASE_URL | sed -n \"s/.*:\([^@]*\)@.*/\1/p\") &&
    psql \$DATABASE_URL -f /tmp/restore.sql --set ON_ERROR_STOP=0 -q &&
    rm -f /tmp/restore.sql &&
    echo \"Checking results...\" &&
    bundle exec rails runner \"
      puts \\\"\\\\n✅ Restore complete!\\\"
      puts \\\"Users: #{User.count}\\\"
      puts \\\"Contacts: #{Contact.count}\\\"
      puts \\\"Campaigns: #{Campaign.count}\\\"
      puts \\\"Landing Pages: #{LandingPage.count}\\\"
      if u = User.first
        puts \\\"\\\\nAdmin email: #{u.email}\\\"
      end
    \"
  '" \
  --region us-east-1
