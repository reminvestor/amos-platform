#!/bin/bash

# Get the latest task definition ARN for agent-marketing-production
TASK_DEFINITION=$(aws ecs list-task-definitions --family-prefix agent-marketing-production --sort DESC --max-items 1 --query 'taskDefinitionArns[0]' --output text)

if [ -z "$TASK_DEFINITION" ]; then
    echo "Error: Could not find task definition for agent-marketing-production"
    exit 1
fi

echo "Using task definition: $TASK_DEFINITION"

# Run the seed task
aws ecs run-task \
    --cluster agent-marketing-prod \
    --task-definition $TASK_DEFINITION \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[subnet-0c57f595255496585,subnet-0243315156673974f],securityGroups=[sg-0412883641d59097a],assignPublicIp=ENABLED}" \
    --overrides '{
        "containerOverrides": [
            {
                "name": "agent-marketing",
                "command": ["bundle", "exec", "rails", "db:seed"]
            }
        ]
    }'

