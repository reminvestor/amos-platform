# Application Health Troubleshooting Guide

Common issues and solutions for AMOS application health.

## Quick Diagnostics

### Health Check Script

```bash
#!/bin/bash
echo "=== AMOS Health Check ==="
echo ""

# Docker
echo "Docker Status:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || echo "❌ Docker not running"
echo ""

# Database
echo "Database Connection:"
docker-compose exec -T web rails runner "ActiveRecord::Base.connection.execute('SELECT 1')" && echo "✅ Connected" || echo "❌ Failed"
echo ""

# Redis (if applicable)
echo "Redis Connection:"
docker-compose exec -T web rails runner "Redis.current.ping == 'PONG' && puts '✅ Connected'" 2>/dev/null || echo "⚠️  Redis not configured or failed"
echo ""

# Tool Catalog
echo "Tool Catalog:"
TOOL_COUNT=$(docker-compose exec -T web rails runner "require 'tools/tool_catalog'; puts Tools::ToolCatalog.instance.all_tools.size" 2>/dev/null)
echo "✅ $TOOL_COUNT tools registered"
echo ""

# Workflows
echo "Workflow Templates:"
WORKFLOW_COUNT=$(find app/workflow_templates -name "*_v2.yml" | wc -l | tr -d ' ')
echo "✅ $WORKFLOW_COUNT templates found"
echo ""
```

## Common Issues

### 1. Docker Not Running

**Symptoms:**
```
Cannot connect to the Docker daemon
docker: command not found
```

**Solutions:**

```bash
# macOS - Start Docker Desktop
open -a Docker

# Check if Docker is starting
ps aux | grep Docker

# Wait for Docker to be ready
until docker ps; do sleep 1; done

# Verify
docker --version
docker ps
```

**Prevention:**
- Add Docker to login items (macOS)
- Check Docker Desktop settings > General > "Start Docker Desktop when you log in"

---

### 2. Containers Not Starting

**Symptoms:**
```
Error response from daemon: driver failed
Container exited with code 1
```

**Diagnosis:**

```bash
# Check container status
docker-compose ps

# View logs for specific container
docker-compose logs web
docker-compose logs db

# Check for port conflicts
lsof -i :3000  # Web port
lsof -i :5432  # PostgreSQL port
lsof -i :6379  # Redis port
```

**Solutions:**

```bash
# Kill process using port
kill -9 $(lsof -t -i:3000)

# Remove and recreate containers
docker-compose down
docker-compose up -d

# Rebuild if needed
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

---

### 3. Database Connection Failed

**Symptoms:**
```
could not connect to server
Connection refused
FATAL: database does not exist
```

**Diagnosis:**

```bash
# Check database container
docker-compose ps db

# Check database logs
docker-compose logs db | tail -50

# Try connecting directly
docker-compose exec db psql -U postgres -l
```

**Solutions:**

```bash
# Database container not running
docker-compose up -d db
sleep 5  # Wait for startup

# Database doesn't exist
docker-compose run --rm web rails db:create

# Database corrupted
docker-compose down
docker volume rm amos_postgres_data
docker-compose up -d db
docker-compose run --rm web rails db:create db:migrate

# Connection string wrong
# Check DATABASE_URL in .env file
cat .env | grep DATABASE_URL
# Should be: postgresql://postgres:postgres@db:5432/amos_development
```

---

### 4. Migrations Pending

**Symptoms:**
```
ActiveRecord::PendingMigrationError
Migrations are pending
```

**Solutions:**

```bash
# Run migrations
docker-compose run --rm web rails db:migrate

# Check migration status
docker-compose run --rm web rails db:migrate:status

# Rollback if needed
docker-compose run --rm web rails db:rollback

# Reset if completely broken
docker-compose run --rm web rails db:drop db:create db:migrate
```

---

### 5. Asset Compilation Errors

**Symptoms:**
```
Asset not found
Sprockets::FileNotFound
```

**Solutions:**

```bash
# Precompile assets
docker-compose run --rm web rails assets:precompile

# Clean and recompile
docker-compose run --rm web rails assets:clobber assets:precompile

# Check JavaScript build
docker-compose run --rm web yarn build

# Install node modules
docker-compose run --rm web yarn install
```

---

### 6. Tool Catalog Empty

**Symptoms:**
```
Tools::ToolCatalog returns empty hash
No tools available in Scout AI
```

**Diagnosis:**

```bash
# Check if tools exist
ls app/services/tools/*.rb

# Try loading catalog
docker-compose run --rm web rails runner "
  require 'tools/tool_catalog'
  catalog = Tools::ToolCatalog.instance
  puts catalog.all_tools.keys
"
```

**Solutions:**

```bash
# Restart Rails to reload
docker-compose restart web

# Check for syntax errors in tools
docker-compose run --rm web rails runner "
  Dir['app/services/tools/*_tool.rb'].each do |file|
    begin
      require file
      puts \"✅ #{file}\"
    rescue => e
      puts \"❌ #{file}: #{e.message}\"
    end
  end
"

# Verify tool extends BaseTool
grep -r "class.*Tool < BaseTool" app/services/tools/
```

---

### 7. Workflow Templates Not Loading

**Symptoms:**
```
Template not found
No matching workflow for user request
```

**Diagnosis:**

```bash
# List templates
ls app/workflow_templates/*_v2.yml

# Validate YAML syntax
docker-compose run --rm web rails runner "
  require 'yaml'
  Dir['app/workflow_templates/*_v2.yml'].each do |file|
    begin
      YAML.load_file(file)
      puts \"✅ #{file}\"
    rescue => e
      puts \"❌ #{file}: #{e.message}\"
    end
  end
"
```

**Solutions:**

```bash
# Fix YAML syntax errors
# Check indentation (must be spaces, not tabs)
# Ensure template_version: 2 is set

# Restart to reload templates
docker-compose restart web
```

---

### 8. Redis Connection Failed

**Symptoms:**
```
Redis::CannotConnectError
Connection refused (Redis)
```

**Solutions:**

```bash
# Start Redis container (if configured)
docker-compose up -d redis

# Check Redis status
docker-compose exec redis redis-cli ping
# Should return: PONG

# Reset Redis data
docker-compose exec redis redis-cli FLUSHALL

# If Redis is optional, disable in config
# Comment out Redis configuration in config/initializers/redis.rb
```

---

### 9. AWS Bedrock Connection Failed

**Symptoms:**
```
Aws::Bedrock::Errors
Invalid credentials
Region not configured
```

**Diagnosis:**

```bash
# Check environment variables
docker-compose exec web env | grep AWS
```

**Solutions:**

```bash
# Add to .env file
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key_here
AWS_SECRET_ACCESS_KEY=your_secret_here

# Restart to load new env vars
docker-compose down
docker-compose up -d

# Test Bedrock connection
docker-compose run --rm web rails runner "
  require 'services/bedrock_service'
  result = BedrockService.new.call_claude(
    [{role: 'user', content: 'test'}],
    []
  )
  puts 'Bedrock connected!' if result
"
```

---

### 10. Out of Memory

**Symptoms:**
```
Killed
Container exits unexpectedly
Rails process crashes
```

**Diagnosis:**

```bash
# Check container memory usage
docker stats

# Check Docker Desktop resources
# Preferences > Resources > Advanced
```

**Solutions:**

```bash
# Increase Docker memory limit
# Docker Desktop > Preferences > Resources > Memory > 4GB+

# Restart containers
docker-compose down
docker-compose up -d

# Check for memory leaks in code
docker-compose logs web | grep "memory"
```

---

### 11. Slow Performance

**Symptoms:**
- Requests taking > 5 seconds
- High CPU usage
- Containers lagging

**Diagnosis:**

```bash
# Check resource usage
docker stats

# Check for N+1 queries
docker-compose logs web | grep "SELECT"

# Profile slow requests
docker-compose logs web | grep "Completed.*in [0-9]{4}ms"
```

**Solutions:**

```bash
# Add database indexes
# Check app/db/migrate for missing indexes on foreign keys

# Enable query caching
# config/environments/development.rb
# config.cache_classes = true

# Use bullet gem to detect N+1
# Check Gemfile for gem 'bullet', group: :development
```

---

### 12. File Permission Errors

**Symptoms:**
```
Permission denied
Cannot write to /app/log
EACCES: permission denied
```

**Solutions:**

```bash
# Fix permissions on host
chmod -R 755 .
chmod -R 777 tmp log

# Run as current user in container
docker-compose exec -u $(id -u):$(id -g) web bash

# Or rebuild with correct user
# In Dockerfile:
# USER app:app
```

---

## Health Check Checklist

Run through this checklist to verify health:

- [ ] Docker Desktop running
- [ ] `docker-compose ps` shows all containers "Up"
- [ ] Database container healthy
- [ ] Can connect to database
- [ ] Migrations current
- [ ] Tool Catalog has tools (>= 20)
- [ ] Workflow templates exist (>= 5)
- [ ] Can start Rails console
- [ ] Assets compiled (production)
- [ ] Environment variables set (AWS, database)
- [ ] No port conflicts
- [ ] Sufficient disk space (>= 10GB free)
- [ ] Sufficient memory (>= 4GB allocated to Docker)

## Monitoring Commands

### Real-Time Monitoring

```bash
# Watch container status
watch -n 2 docker-compose ps

# Follow all logs
docker-compose logs -f

# Monitor resource usage
docker stats

# Watch specific log file
docker-compose exec web tail -f log/development.log
```

### Health Endpoints

```bash
# Application health (if implemented)
curl http://localhost:3000/health

# Database health
docker-compose exec db pg_isready

# Redis health
docker-compose exec redis redis-cli ping
```

## Recovery Procedures

### Full Reset (Nuclear Option)

⚠️ **Destroys all data**

```bash
# Stop everything
docker-compose down -v

# Remove images
docker-compose down --rmi all

# Clean Docker system
docker system prune -a --volumes -f

# Rebuild from scratch
docker-compose build --no-cache
docker-compose up -d
docker-compose run --rm web rails db:create db:migrate db:seed

# Verify
docker-compose ps
docker-compose run --rm web rails runner "puts User.count"
```

### Gentle Reset

Keeps Docker images, rebuilds data:

```bash
# Stop containers, remove volumes
docker-compose down -v

# Start fresh
docker-compose up -d
docker-compose run --rm web rails db:create db:migrate db:seed
```

## Resources

- [Docker Troubleshooting](https://docs.docker.com/config/daemon/troubleshoot/)
- [Rails Troubleshooting](https://guides.rubyonrails.org/debugging_rails_applications.html)
- [PostgreSQL Common Errors](https://www.postgresql.org/docs/current/errcodes-appendix.html)
- Project logs: `docker-compose logs`
- Application logs: `log/development.log`
