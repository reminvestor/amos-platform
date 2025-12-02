# /health Command

Check application health status and Docker services.

## Usage

```
/health
```

## What This Command Does

Invokes the **Checking Application Health** skill to:
- ✅ Verify Docker services are running
- ✅ Check Rails server status
- ✅ Verify database connectivity
- ✅ Check background job processing (SolidQueue)
- ✅ Review recent logs for errors
- ✅ Verify critical services (Redis, PostgreSQL)

## Instructions

Use the Skill tool to invoke the `checking-application-health` skill to perform a comprehensive health check of the application and its dependencies.
