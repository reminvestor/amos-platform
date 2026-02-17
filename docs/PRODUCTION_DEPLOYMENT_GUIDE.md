# Production Deployment Guide

This guide covers deploying AMOS to production with best practices for security, performance, and reliability.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Hosting Platform Options](#hosting-platform-options)
- [Environment Configuration](#environment-configuration)
- [Database Setup](#database-setup)
- [Row-Level Security (RLS)](#row-level-security-rls)
- [Deployment Steps](#deployment-steps)
- [Post-Deployment Checklist](#post-deployment-checklist)
- [Monitoring & Logging](#monitoring--logging)
- [Backup & Recovery](#backup--recovery)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before deploying to production, ensure you have:

- ✅ All tests passing (`rails test`)
- ✅ Database migrations applied (`rails db:migrate`)
- ✅ Environment variables documented (see `.env.example`)
- ✅ AWS account with Bedrock access
- ✅ S3 bucket for RAG document storage
- ✅ PostgreSQL 16+ with pgvector extension
- ✅ Redis instance for caching

---

## Hosting Platform Options

### Option 1: AWS ECS Fargate (Recommended for Scale)

**Pros:**
- Docker-native (use existing Dockerfile)
- Auto-scaling capabilities
- Full AWS integration (Bedrock, S3, RDS)
- Production-grade monitoring

**Cons:**
- Higher complexity
- Higher cost for small workloads

**Cost Estimate:** $50-200/month (depends on usage)

**Quick Start:**
```bash
# Install AWS CLI and ECS CLI
brew install aws-cli ecs-cli

# Configure ECS cluster
ecs-cli configure --cluster amos-production --region us-east-1

# Deploy
ecs-cli up --capability-iam
docker-compose -f docker-compose.prod.yml push
ecs-cli compose service up
```

### Option 2: Render.com (Recommended for MVP)

**Pros:**
- Simplest deployment (connects to GitHub)
- Auto-deploy on git push
- Managed PostgreSQL + Redis
- Free SSL certificates
- Good for MVP/small teams

**Cons:**
- Less control than AWS
- Can get expensive at scale

**Cost Estimate:** $25-75/month (Starter tier)

**Quick Start:**
1. Connect GitHub repository to Render
2. Create PostgreSQL database (with pgvector)
3. Create Redis instance
4. Create Web Service (Docker)
5. Set environment variables
6. Deploy

### Option 3: Fly.io (Recommended for Edge Performance)

**Pros:**
- Global edge deployment
- Fast for international users
- Docker-native
- Competitive pricing

**Cons:**
- Newer platform (less mature)
- PostgreSQL setup more manual

**Cost Estimate:** $20-60/month

**Quick Start:**
```bash
# Install Fly CLI
brew install flyctl

# Login and launch
flyctl auth login
flyctl launch

# Deploy
flyctl deploy
```

### Option 4: Heroku (Classic SaaS Platform)

**Pros:**
- Very simple setup
- Great for Rails apps
- Mature platform

**Cons:**
- More expensive than alternatives
- Less control

**Cost Estimate:** $50-150/month

---

## Environment Configuration

### Required Environment Variables

Create a `.env.production` file (DO NOT commit to git):

```bash
# === CRITICAL (Will not boot without these) ===
SECRET_KEY_BASE=<generate with: rails secret>
DATABASE_URL=postgresql://user:pass@host:5432/amos_production
REDIS_URL=redis://host:6379/0

# === AWS (Required for AI features) ===
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=<your-key>
AWS_SECRET_ACCESS_KEY=<your-secret>

# === RAG Document Storage ===
RAG_BUCKET=amos-production-rag-docs
AWS_S3_ENDPOINT=  # Leave blank for real S3 (not LocalStack)

# === OpenAI (Required for RAG embeddings) ===
OPENAI_API_KEY=sk-<your-key>
OPENAI_EMBEDDING_MODEL=text-embedding-ada-002

# === Application Settings ===
RAILS_ENV=production
RAILS_LOG_LEVEL=info
RAILS_SERVE_STATIC_FILES=true  # If not using CDN
RAILS_MAX_THREADS=5
WEB_CONCURRENCY=2

# === Optional but Recommended ===
MAILGUN_API_KEY=<your-key>
MAILGUN_DOMAIN=mg.yourdomain.com
ELEVEN_LABS_API_KEY=<your-key>
DEEPGRAM_API_KEY=<your-key>  # Fallback for voice
GEMINI_API_KEY=<your-key>  # For image generation

# === Row-Level Security ===
ENABLE_RLS=true  # CRITICAL: Enables multi-tenant data isolation

# === Security Headers ===
FORCE_SSL=true
HSTS_MAX_AGE=31536000
```

### Generating SECRET_KEY_BASE

```bash
docker compose exec web rails secret
# Copy output to .env.production
```

### Managing Secrets

**AWS Secrets Manager (Recommended):**
```bash
aws secretsmanager create-secret \
  --name amos/production/env \
  --secret-string file://.env.production
```

**Doppler (Alternative):**
```bash
doppler setup
doppler secrets upload .env.production
```

---

## Database Setup

### Option 1: AWS RDS PostgreSQL (Recommended)

1. **Create RDS Instance:**
   ```bash
   aws rds create-db-instance \
     --db-instance-identifier amos-production \
     --db-instance-class db.t4g.medium \
     --engine postgres \
     --engine-version 16.1 \
     --master-username amos_admin \
     --master-user-password <secure-password> \
     --allocated-storage 100 \
     --backup-retention-period 7 \
     --multi-az \
     --storage-encrypted \
     --enable-cloudwatch-logs-exports postgresql
   ```

2. **Enable pgvector Extension:**
   ```sql
   -- Connect to database and run:
   CREATE EXTENSION IF NOT EXISTS vector;
   ```

3. **Run Migrations:**
   ```bash
   rails db:migrate RAILS_ENV=production
   ```

### Option 2: Render.com Managed PostgreSQL

1. Create PostgreSQL database in Render dashboard
2. Select PostgreSQL 16
3. Choose plan (Starter: $7/month)
4. Copy DATABASE_URL to environment
5. Run migrations via Render shell or deploy

### Automated Backups

**AWS RDS:**
- Automated backups enabled by default
- Point-in-time recovery (up to 35 days)
- Manual snapshots recommended before major changes

**Render.com:**
- Daily automated backups
- 7-day retention
- Manual backups available

---

## Row-Level Security (RLS)

**CRITICAL:** RLS must be enabled in production to prevent multi-tenant data leakage.

### Enabling RLS

1. **Run Migration:**
   ```bash
   rails db:migrate RAILS_ENV=production
   # This runs 20260217010633_enable_row_level_security.rb
   ```

2. **Verify RLS Enabled:**
   ```sql
   -- Connect to database and check:
   SELECT tablename, rowsecurity
   FROM pg_tables
   WHERE schemaname = 'public'
   AND rowsecurity = true;

   -- Should return 161 tables
   ```

3. **Set Environment Variable:**
   ```bash
   ENABLE_RLS=true
   ```

### How RLS Works

1. **Session Variable:** Each request sets `app.current_entity_id` in PostgreSQL session
2. **Policy Enforcement:** Database automatically filters all queries by entity_id
3. **Automatic:** No code changes needed - policies enforce at DB level

### Testing RLS Locally

```bash
# Enable RLS in development
export ENABLE_RLS=true

# Run migrations
docker compose exec web rails db:migrate

# Test with rails console
docker compose exec web rails console

# In console:
ActiveRecord::Base.connection.execute("SET LOCAL app.current_entity_id = 1;")
Campaign.all  # Should only return campaigns for entity_id = 1

ActiveRecord::Base.connection.execute("SET LOCAL app.current_entity_id = 2;")
Campaign.all  # Should only return campaigns for entity_id = 2
```

### Disabling RLS (Emergency Only)

If RLS causes production issues (should not happen if tested):

```sql
-- Disable RLS on specific table (emergency only)
ALTER TABLE campaigns DISABLE ROW LEVEL SECURITY;

-- Re-enable when fixed
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
```

---

## Deployment Steps

### AWS ECS Deployment

1. **Build and Push Docker Image:**
   ```bash
   # Build production image
   docker build -f Dockerfile -t amos-production:latest .

   # Tag for ECR
   aws ecr get-login-password | docker login --username AWS --password-stdin <aws-account-id>.dkr.ecr.us-east-1.amazonaws.com
   docker tag amos-production:latest <aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/amos:latest

   # Push
   docker push <aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/amos:latest
   ```

2. **Create ECS Task Definition:**
   ```json
   {
     "family": "amos-production",
     "networkMode": "awsvpc",
     "requiresCompatibilities": ["FARGATE"],
     "cpu": "1024",
     "memory": "2048",
     "containerDefinitions": [
       {
         "name": "web",
         "image": "<aws-account-id>.dkr.ecr.us-east-1.amazonaws.com/amos:latest",
         "portMappings": [{"containerPort": 3000}],
         "environment": [
           {"name": "RAILS_ENV", "value": "production"},
           {"name": "ENABLE_RLS", "value": "true"}
         ],
         "secrets": [
           {"name": "SECRET_KEY_BASE", "valueFrom": "arn:aws:secretsmanager:..."},
           {"name": "DATABASE_URL", "valueFrom": "arn:aws:secretsmanager:..."}
         ]
       }
     ]
   }
   ```

3. **Deploy Service:**
   ```bash
   aws ecs create-service \
     --cluster amos-production \
     --service-name amos-web \
     --task-definition amos-production:1 \
     --desired-count 2 \
     --launch-type FARGATE
   ```

### Render.com Deployment

1. **Connect Repository:**
   - Go to Render dashboard
   - Click "New Web Service"
   - Connect GitHub repository

2. **Configure Service:**
   - Name: amos-production
   - Environment: Docker
   - Dockerfile path: Dockerfile
   - Plan: Starter ($7/month)

3. **Set Environment Variables:**
   - Add all variables from `.env.example`
   - Mark secrets as "secret" (encrypted)

4. **Deploy:**
   - Click "Create Web Service"
   - Render automatically deploys on push to main

### Fly.io Deployment

1. **Initialize:**
   ```bash
   flyctl launch
   # Follow prompts to configure
   ```

2. **Set Secrets:**
   ```bash
   flyctl secrets set SECRET_KEY_BASE=<value>
   flyctl secrets set DATABASE_URL=<value>
   # ... repeat for all secrets
   ```

3. **Deploy:**
   ```bash
   flyctl deploy
   ```

---

## Post-Deployment Checklist

### Health Checks

```bash
# Check application health
curl https://your-domain.com/health

# Expected response:
# {"status":"ok","timestamp":"2026-02-17T01:06:33Z"}

# Check database connection
curl https://your-domain.com/up

# Expected: HTTP 200 OK
```

### Smoke Tests

1. ✅ User can sign up
2. ✅ User can log in
3. ✅ User can create entity
4. ✅ Scout chat loads
5. ✅ AI response works (tests Bedrock connection)
6. ✅ File upload works (tests S3 connection)
7. ✅ Email sending works (tests Mailgun)
8. ✅ Voice input works (tests Eleven Labs)

### Security Verification

```bash
# Check SSL is enabled
curl -I https://your-domain.com
# Should see: Strict-Transport-Security header

# Check RLS is enabled
# Connect to production database:
SELECT tablename, rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
AND tablename = 'campaigns';

# Should return: rowsecurity = true
```

### Performance Baseline

```bash
# Measure response times
curl -w "@curl-format.txt" -o /dev/null -s https://your-domain.com

# curl-format.txt:
time_namelookup:  %{time_namelookup}\n
time_connect:  %{time_connect}\n
time_starttransfer:  %{time_starttransfer}\n
time_total:  %{time_total}\n

# Target: < 500ms for homepage
```

---

## Monitoring & Logging

### Application Monitoring (Choose One)

**Option 1: Scout APM (Recommended for Rails)**
```ruby
# Gemfile
gem 'scout_apm'

# config/scout_apm.yml
production:
  name: AMOS Production
  key: <%= ENV['SCOUT_KEY'] %>
  monitor: true
```

**Option 2: New Relic (Free Tier Available)**
```ruby
# Gemfile
gem 'newrelic_rpm'

# config/newrelic.yml
# Download from New Relic dashboard
```

**Option 3: Skylight (Rails-specific)**
```ruby
# Gemfile
gem 'skylight'
```

### Error Tracking (Without Sentry)

**Option 1: Rails Error Reporter + Slack**
```ruby
# config/initializers/error_handling.rb
Rails.error.subscribe do |event|
  SlackNotifier.post(
    text: "Error in production: #{event.error.message}",
    channel: '#amos-errors'
  )
end
```

**Option 2: Honeybadger**
```ruby
# Gemfile
gem 'honeybadger'

# config/honeybadger.yml
api_key: <%= ENV['HONEYBADGER_API_KEY'] %>
```

**Option 3: Rollbar**
```ruby
# Gemfile
gem 'rollbar'

# config/initializers/rollbar.rb
Rollbar.configure do |config|
  config.access_token = ENV['ROLLBAR_ACCESS_TOKEN']
end
```

### Log Aggregation

**Option 1: Papertrail (Simple, Free Tier)**
```bash
# Add to Gemfile
gem 'remote_syslog_logger'

# config/environments/production.rb
config.logger = RemoteSyslogLogger.new('logs.papertrailapp.com', <port>)
```

**Option 2: AWS CloudWatch Logs**
```bash
# Install CloudWatch agent on ECS
# Logs automatically shipped to CloudWatch
```

### Uptime Monitoring

**UptimeRobot (Free for 50 monitors):**
- Monitor: https://your-domain.com/health
- Interval: 5 minutes
- Alert: Email/Slack when down

**Better Uptime (Modern alternative):**
- More detailed status pages
- Incident management
- $18/month

---

## Backup & Recovery

### Automated Database Backups

**AWS RDS:**
```bash
# Backups are automatic (configured at creation)
# Verify backup window:
aws rds describe-db-instances \
  --db-instance-identifier amos-production \
  --query 'DBInstances[0].PreferredBackupWindow'
```

**Render.com:**
- Automatic daily backups (7-day retention)
- Manual backups via dashboard

### Manual Backup (Pre-Deployment)

```bash
# Create snapshot before major changes
pg_dump $DATABASE_URL > amos_backup_$(date +%Y%m%d).sql
gzip amos_backup_*.sql

# Upload to S3
aws s3 cp amos_backup_*.sql.gz s3://amos-backups/
```

### Recovery Testing

Test recovery quarterly:

```bash
# 1. Create test database
createdb amos_recovery_test

# 2. Restore from backup
gunzip -c amos_backup_20260217.sql.gz | psql amos_recovery_test

# 3. Verify data integrity
psql amos_recovery_test -c "SELECT COUNT(*) FROM campaigns;"

# 4. Drop test database
dropdb amos_recovery_test
```

---

## Troubleshooting

### Issue: Tests Passing Locally, Failing in Production

**Possible Cause:** Environment variable missing

**Solution:**
```bash
# Check all env vars are set
docker compose exec web rails runner "puts ENV.keys.sort"

# Compare with .env.example
diff <(grep "^[A-Z]" .env.example | cut -d= -f1 | sort) \
     <(docker compose exec web rails runner "puts ENV.keys.sort")
```

### Issue: Database Connection Timeouts

**Possible Cause:** Connection pool exhausted

**Solution:**
```ruby
# config/database.yml
production:
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 }.to_i + 5 %>
  # Add 5 extra connections for background jobs
```

### Issue: RLS Blocking Queries

**Symptoms:** Queries return empty results unexpectedly

**Debug:**
```sql
-- Check current entity context
SELECT current_setting('app.current_entity_id', true);

-- Should return entity ID, not NULL

-- If NULL, RLS context not set - check ApplicationController
```

### Issue: Bedrock Rate Limiting

**Symptoms:** AI responses failing with 429 errors

**Solution:**
```ruby
# config/initializers/bedrock.rb
BedrockService.configure do |config|
  config.max_retries = 3
  config.retry_delay = 2.seconds
  config.backoff_multiplier = 2
end
```

### Issue: Out of Memory (OOM)

**Symptoms:** Container restarts, 502 errors

**Solution:**
```bash
# Increase container memory (ECS)
aws ecs update-service \
  --cluster amos-production \
  --service amos-web \
  --task-definition amos-production:2  # Updated with more memory

# Or reduce workers
export WEB_CONCURRENCY=1  # Instead of 2
```

---

## Performance Optimization

### Database Indexes

```bash
# Run after deployment
docker compose exec web rails db:migrate

# Verify indexes exist
psql $DATABASE_URL -c "\di"
```

### Enable CDN (CloudFront)

```bash
# 1. Create CloudFront distribution
aws cloudfront create-distribution \
  --origin-domain-name your-domain.com

# 2. Point to assets
# config/environments/production.rb
config.asset_host = 'd12345abcdef.cloudfront.net'
```

### Prompt Caching

```bash
# When AWS Bedrock supports it:
BEDROCK_PROMPT_CACHING_ENABLED=true
# Saves 49% on AI costs
```

---

## Security Hardening

### SSL/TLS (Automatic on All Platforms)

- Render: Auto-provisions Let's Encrypt
- AWS ALB: Use ACM (AWS Certificate Manager)
- Fly.io: Auto-provisions certificates

### Security Headers

```ruby
# Gemfile
gem 'secure_headers'

# config/initializers/secure_headers.rb
SecureHeaders::Configuration.default do |config|
  config.hsts = "max-age=#{1.year.to_i}"
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "1; mode=block"
  config.referrer_policy = "strict-origin-when-cross-origin"
end
```

### Rate Limiting

See next section for Rack::Attack configuration.

---

## Next Steps

After successful deployment:

1. ✅ Monitor error rates (first 24 hours)
2. ✅ Test all critical user flows
3. ✅ Verify RLS is working (multi-tenant isolation)
4. ✅ Set up alerting (uptime + errors)
5. ✅ Document any production-specific issues
6. ✅ Schedule first backup test
7. ✅ Plan scaling strategy (if needed)

---

## Support

For deployment issues:
- Check logs: `docker compose logs -f web`
- Review health endpoint: `/health`
- Consult CLAUDE.md for architecture
- Open GitHub issue for bugs

**Last Updated:** 2026-02-17
**Tested Platforms:** Render.com, AWS ECS, Fly.io
**Minimum Rails Version:** 8.0.1
