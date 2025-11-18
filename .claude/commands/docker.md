# /docker Command

Manage Docker development environment.

## Usage

```
/docker [action]
```

## What This Command Does

Invokes the **Managing Docker Development** skill to:
- ✅ Start/stop all services (web, db, redis, mailhog)
- ✅ View container logs
- ✅ Execute commands in containers
- ✅ Restart individual services
- ✅ Reset and cleanup containers
- ✅ Check service status
- ✅ Database operations via Docker

## Services Managed

- **web** - Rails application
- **db** - PostgreSQL database
- **redis** - Cache and job queue
- **mailhog** - Email testing

## Examples

```
# Start all services
/docker start

# View logs
/docker logs

# Execute command in container
/docker exec web rails console

# Check status
/docker status

# Stop all services
/docker stop

# Reset and cleanup
/docker reset
```

## Common Tasks

**View Rails logs:**
```
/docker logs web
```

**Open Rails console:**
```
/docker exec web rails console
```

**Check database:**
```
/docker exec db psql -U postgres -d agent_marketing_dev
```

## Instructions

Use the Skill tool to invoke the `managing-docker-development` skill to manage Docker services based on the user's request. If no specific action is provided, show available Docker commands and current service status.
