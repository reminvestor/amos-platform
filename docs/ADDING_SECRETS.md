# Adding New Secrets to Production

## Quick Guide

Adding a new secret is a simple 3-step process:

### Step 1: Create the Secret in AWS Secrets Manager

```bash
# Create the secret
aws secretsmanager create-secret \
    --name "agent-marketing-YOUR_SECRET_NAME" \
    --secret-string "your-secret-value" \
    --description "Description of what this secret is for" \
    --region us-east-1

# Or update if it already exists
aws secretsmanager update-secret \
    --secret-id "agent-marketing-YOUR_SECRET_NAME" \
    --secret-string "your-secret-value" \
    --region us-east-1
```

### Step 2: Add to Task Definition

Edit `aws/task-definition.json` and add your secret to BOTH containers:

```json
{
  "name": "YOUR_ENV_VAR_NAME",
  "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-YOUR_SECRET_NAME-XXXXXX"
}
```

**Add it in TWO places:**
1. Line ~95: Main `agent-marketing` container secrets array
2. Line ~190: `solid-queue-worker` container secrets array

**Pro tip:** Copy an existing secret entry and modify it.

### Step 3: Give ECS Execution Role Permission

The execution role needs permission to read the secret:

```bash
# Add to the existing execution role policy
aws iam put-role-policy \
  --role-name agent-marketing-ecs-execution-role \
  --policy-name your-secret-access \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-YOUR_SECRET_NAME-*"
    }]
  }'
```

### Step 4: Deploy

```bash
git add aws/task-definition.json
git commit -m "Add YOUR_SECRET_NAME to production"
git push origin main
git push origin prod  # Triggers automatic deployment
```

**That's it!** The CI/CD pipeline will:
- Pull the updated task-definition.json from Git
- Register a new task definition with ALL secrets (including your new one)
- Deploy to ECS
- Your new secret will be available as `ENV['YOUR_ENV_VAR_NAME']`

---

## Examples

### Adding Stripe API Key

```bash
# 1. Create secret
aws secretsmanager create-secret \
    --name "agent-marketing-stripe-api-key" \
    --secret-string "sk_live_..." \
    --region us-east-1

# 2. Add to task-definition.json (both containers)
{
  "name": "STRIPE_API_KEY",
  "valueFrom": "arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-stripe-api-key-AbCdEf"
}

# 3. Add permission
aws iam put-role-policy --role-name agent-marketing-ecs-execution-role \
  --policy-name stripe-secret-access \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["secretsmanager:GetSecretValue"],"Resource":"arn:aws:secretsmanager:us-east-1:637423327454:secret:agent-marketing-stripe-api-key-*"}]}'

# 4. Deploy
git add aws/task-definition.json
git commit -m "Add Stripe API key"
git push origin prod
```

---

## Troubleshooting

### Secret not available after deployment
- Check the task definition has the secret: `aws ecs describe-task-definition --task-definition agent-marketing:LATEST`
- Check ECS execution role has permission
- Check the secret ARN is correct (including the 6-char suffix)

### How to get the secret ARN
```bash
aws secretsmanager describe-secret \
  --secret-id "agent-marketing-YOUR_SECRET_NAME" \
  --query 'ARN' \
  --output text
```

### Verify secret is loaded in container
```bash
# Connect to running container
aws ecs execute-command \
  --cluster agent-marketing-cluster \
  --task TASK_ID \
  --container agent-marketing \
  --interactive \
  --command "/bin/bash"

# Then in container:
echo $YOUR_ENV_VAR_NAME
```

---

## Best Practices

1. **Always use the naming pattern**: `agent-marketing-SECRET_NAME`
2. **Always add to BOTH containers** in task-definition.json
3. **Always test locally first** with `.env` file
4. **Document what the secret is for** in the description
5. **Rotate secrets regularly** for security

---

## Current Secrets

All secrets follow this pattern in Secrets Manager:
- `agent-marketing-database-url`
- `agent-marketing-rails-master-key`  
- `agent-marketing-redis-url`
- `agent-marketing-mailgun-api-key`
- `agent-marketing-mailgun-domain`
- `agent-marketing-pinecone-api-key`
- `agent-marketing-pinecone-environment`
- `agent-marketing-pinecone-index-name`
- `agent-marketing-openai-api-key`
- `agent-marketing-anthropic-api-key`
- `agent-marketing-deepgram-api-key` ✨
- `agent-marketing-deepgram-webhook-secret` ✨


