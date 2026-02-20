# Container Setup Guide for AMOS with Agent Lightning

## 🚀 Quick Start

### 1. Required Environment Variables

Before starting services, make sure your `.env` file contains these required variables:

```bash
# AWS Bedrock (Required for AI features)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your-access-key-here
AWS_SECRET_ACCESS_KEY=your-secret-key-here

# Optional but recommended
OPENAI_API_KEY=sk-your-key-here  # For embeddings
```

### 2. Start Container Services

```bash
# Start all services including Agent Lightning
podman compose up -d

# Or start with logs visible
podman compose up
```

### 3. Verify Services Are Running

```bash
# Check all services status
podman compose ps

# Expected output should show:
# - db (PostgreSQL with pgvector)
# - redis
# - localstack (for S3 emulation)
# - web (Rails app on port 3000)
# - worker (SolidQueue)
# - agent_lightning (Python service on ports 4747/4748)
```

### 4. Test Agent Lightning Service

```bash
# Health check
curl http://localhost:4747/health

# View logs
podman compose logs -f agent_lightning

# Check metrics
curl http://localhost:4747/metrics
```

### 5. Access the Application

- Rails App: http://localhost:3000
- Agent Lightning API: http://localhost:4747
- Agent Lightning Store: http://localhost:4748

### 6. Common Commands

```bash
# Stop all services
podman compose down

# Rebuild after code changes
podman compose build agent_lightning
podman compose up -d agent_lightning

# View Rails logs
podman compose logs -f web

# Access Rails console
podman compose exec web rails console

# Run database migrations
podman compose exec web rails db:migrate
```

## 🔧 Troubleshooting

### Agent Lightning Not Starting

1. Check logs:
   ```
   podman compose logs agent_lightning
   ```

2. Verify database connection:
   ```
   podman compose exec agent_lightning python -c "from config import config; print(config.database_url)"
   ```

3. Test startup script:
   ```
   podman compose exec agent_lightning bash test_startup.sh
   ```

### AWS Credentials Issues

If you see AWS credential warnings, add to your `.env`:
```
AWS_ACCESS_KEY_ID=your-key
AWS_SECRET_ACCESS_KEY=your-secret
```

### Port Conflicts

If ports are already in use:
- Rails (3000): Change in compose.yaml
- Agent Lightning (4747/4748): Change in compose.yaml
- PostgreSQL (5432): Change in compose.yaml

## 🎯 Next Steps for AWS Deployment

Once local testing is complete:

1. **Dev Environment**:
   - Update ECS task definition with agent_lightning container
   - Add service discovery for inter-container communication
   - Update security groups for ports 4747/4748

2. **Production Environment**:
   - Create separate ECS service for agent_lightning
   - Configure auto-scaling
   - Set up CloudWatch monitoring
   - Update ALB target groups if needed
