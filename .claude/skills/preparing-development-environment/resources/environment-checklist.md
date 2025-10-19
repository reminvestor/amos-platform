# Development Environment Checklist

Manual verification steps for environment setup.

## Prerequisites

- [ ] Docker Desktop installed and running
- [ ] Git repository cloned
- [ ] `.env` file configured (see `.env.example`)
- [ ] Port 3000 available (no other Rails apps running)

## Automated Setup Verification

After running `preparing-development-environment` skill:

### Docker Containers
- [ ] Web container running (`docker-compose ps`)
- [ ] Database container running
- [ ] Redis container running (if applicable)

### Database
- [ ] Migrations current (`rails db:migrate:status`)
- [ ] Can connect via Rails console
- [ ] Test entity exists (if created)

### Application Access
- [ ] Main app loads at `http://app.localhost:3000`
- [ ] Can sign in with admin credentials
- [ ] Scout AI chat accessible at `/scout`
- [ ] No JavaScript errors in browser console

### Documentation
- [ ] `docs/SCOUT_TOOLS.md` exists and current
- [ ] `docs/WORKFLOW_TEMPLATES.md` exists (if updated)
- [ ] `docs/MODELS_REFERENCE.md` exists (if updated)

## Common Issues

### Docker Not Running
```bash
# Check Docker status
docker ps

# Start Docker Desktop application
open -a Docker
```

### Port Already in Use
```bash
# Find process using port 3000
lsof -i :3000

# Kill the process
kill -9 <PID>
```

### Database Connection Failed
```bash
# Recreate database
docker-compose run --rm web rails db:drop db:create db:migrate

# Check database container logs
docker-compose logs db
```

### Containers Won't Start
```bash
# Reset Docker environment
docker-compose down -v
docker-compose up -d

# Rebuild containers
docker-compose build
docker-compose up -d
```

## Manual Setup (Alternative)

If automated setup fails, run these commands manually:

```bash
# 1. Start containers
docker-compose up -d

# 2. Create and migrate database
docker-compose run --rm web rails db:create db:migrate

# 3. Create entity
docker-compose run --rm web rails runner "
  entity = Entity.create!(name: 'Test Entity', subdomain: 'test')
  User.create!(
    entity: entity,
    email: 'admin@test.test',
    password: 'password123',
    password_confirmation: 'password123'
  )
"

# 4. Verify
docker-compose run --rm web rails console
# In console: Entity.count (should be > 0)
```

## Health Check Commands

```bash
# Check all containers
docker-compose ps

# Check web logs
docker-compose logs -f web

# Check database
docker-compose run --rm web rails runner "puts ActiveRecord::Base.connection.execute('SELECT 1').to_a"

# Check tool catalog
docker-compose run --rm web rails runner "require 'tools/tool_catalog'; puts Tools::ToolCatalog.instance.all_tools.size"

# Check workflow templates
ls -l app/workflow_templates/*.yml | wc -l
```

## Environment Variables

Required in `.env`:

```bash
# AWS Bedrock (for Scout AI)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret

# Database
DATABASE_URL=postgresql://postgres:postgres@db:5432/amos_development

# Optional
MAILGUN_API_KEY=your_mailgun_key
REDIS_URL=redis://redis:6379/0
```

## Verification Script

Quick verification of complete setup:

```bash
#!/bin/bash
echo "Checking Docker..."
docker ps >/dev/null 2>&1 && echo "✅ Docker running" || echo "❌ Docker not running"

echo "Checking database..."
docker-compose run --rm web rails runner "ActiveRecord::Base.connection" >/dev/null 2>&1 && echo "✅ Database connected" || echo "❌ Database connection failed"

echo "Checking entities..."
ENTITY_COUNT=$(docker-compose run --rm web rails runner "puts Entity.count" 2>/dev/null | tail -1)
echo "✅ Entities: $ENTITY_COUNT"

echo "Checking tools..."
TOOL_COUNT=$(docker-compose run --rm web rails runner "require 'tools/tool_catalog'; puts Tools::ToolCatalog.instance.all_tools.size" 2>/dev/null | tail -1)
echo "✅ Tools registered: $TOOL_COUNT"

echo "Checking workflows..."
WORKFLOW_COUNT=$(ls app/workflow_templates/*_v2.yml 2>/dev/null | wc -l | tr -d ' ')
echo "✅ Workflows: $WORKFLOW_COUNT"
```
