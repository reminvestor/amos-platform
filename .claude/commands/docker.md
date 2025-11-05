# Docker Management

Manage Docker containers for development environment.

## Description

Interactive menu for Docker operations including:
- Start/stop all services
- View container logs
- Execute commands in containers
- Restart individual services
- Reset containers
- Database operations via Docker

## Services Managed

- **web** - Rails application
- **db** - PostgreSQL database
- **redis** - Cache and job queue
- **mailhog** - Email testing

## When to Use

- Starting development session
- Stopping when done
- Debugging service issues
- Running commands in containers
- Database operations
- Checking logs

## Interactive Menu

```bash
.claude/skills/managing-docker-development/scripts/docker-action.sh
```

Options:
1. Start all services
2. Stop all services
3. View logs
4. Execute command in container
5. Restart specific service
6. Reset and cleanup
7. Status check

## Common Tasks

**View Rails logs:**
```
Select: 3 (View logs)
Select: web (Rails container)
```

**Open Rails console:**
```
Select: 4 (Execute command)
Select: web
Command: rails console
```

**Check database:**
```
Select: 4 (Execute command)
Select: db
Command: psql -U postgres -d agent_marketing_dev
```

## Status

Returns running/stopped status for all services.
