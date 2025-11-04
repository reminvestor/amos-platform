# Check Deployment

Comprehensive health checks for all environments (local dev, staging, production).

## Description

Verifies application health and deployment status including:
- Application uptime and responsiveness
- Server health metrics (Docker, database, Redis)
- Database connectivity and integrity
- Background job queue status
- Error rates and recent logs
- Environment variable validation
- Dependency health (gems, packages)
- Asset compilation status
- Performance metrics

## When to Use

**Local Development:**
- Verifying development setup after starting services
- Debugging connection issues (Docker, database, Redis)
- Confirming all services are running
- Pre-work validation
- Troubleshooting unexpected behavior

**Staging & Production:**
- After deploying changes
- Monitoring application health
- Investigating issues or errors
- Pre-release checks
- Performance verification
- Continuous monitoring

## Environments

- Development
- Staging
- Production

## What Gets Checked

- ✅ HTTP response codes
- ✅ Database connection pool
- ✅ Background job queue
- ✅ Redis connectivity
- ✅ Disk space usage
- ✅ Error logs
- ✅ Recent deployments
- ✅ Performance metrics

## Usage

```bash
.claude/skills/checking-deployments/scripts/check-deployment.sh
```

You'll be prompted to select:
1. Environment (dev/staging/prod)
2. Service to check
3. Verbosity level

## Output

- 🟢 Green: Healthy
- 🟡 Yellow: Degraded
- 🔴 Red: Critical
- 📊 Metrics and timestamps
- 🔗 Links to logs and dashboards

## Continuous Monitoring

Run periodically or integrate with:
- Cron jobs
- Monitoring services
- CI/CD pipelines
- Alert systems
