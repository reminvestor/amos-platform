# Managing Docker Development

Comprehensive Docker Compose management for the AMOS development environment.

## Description

This skill provides complete control over the AMOS Docker Compose development stack including Rails, PostgreSQL, Redis, and RAG services. It handles starting/stopping services, database operations, Rails console access, testing, log viewing, and RAG-specific operations.

**Use this skill when:**
- Starting or stopping the development environment
- Running database migrations or seeds
- Accessing Rails console or bash shell
- Viewing service logs
- Running tests in Docker
- Managing RAG system (Docling, Pinecone integration)
- Troubleshooting Docker issues

## Instructions

### Service Stack

The AMOS development environment includes:
- **web** - Rails 8 application (port 3000)
- **db** - PostgreSQL database (port 5432)
- **redis** - Redis cache (port 6379)

### Available Actions

**1. start** - Start all services in detached mode
**2. stop** - Stop all services
**3. restart** - Restart services (all or specific)
**4. rebuild** - Rebuild images and restart
**5. logs** - View service logs (follow mode)
**6. console** - Open Rails console
**7. db** - Database operations (migrate, rollback, seed, reset, drop)
**8. shell** - Open bash shell in web container
**9. ps** - Show container status
**10. clean** - Clean up containers and volumes
**11. test** - Run tests (all, model, controller, system, or specific)
**12. rag** - RAG system operations (health, verify, seed, list, test)

### Database Operations

**migrate** - Run pending migrations
```bash
docker-compose exec web rails db:migrate
```

**rollback** - Rollback last migration
```bash
docker-compose exec web rails db:rollback
```

**seed** - Populate database with seed data
```bash
docker-compose exec web rails db:seed
```

**reset** - Drop, create, migrate, and seed (destructive!)
```bash
docker-compose exec web rails db:reset
```

**drop** - Complete database wipe (requires confirmation)
```bash
docker-compose exec web rails db:drop db:create db:migrate db:seed
```

### RAG Operations

**health** - Check RAG system status
```bash
docker-compose exec web rails rag:health
```

**verify** - Verify Docling and environment variables
- Checks Docling Python package
- Verifies OPENAI_API_KEY present
- Verifies PINECONE_API_KEY present

**seed** - Populate system RAG stores
```bash
docker-compose exec web rails rag:populate_system
```

**list** - List all RAG stores
```bash
docker-compose exec web rails rag:list
```

**test** - Test RAG functionality end-to-end
- Creates test user/entity if needed
- Creates sample RAG store
- Verifies storage successful

### Testing Modes

**all** - Run complete test suite
**model** - Run model tests only
**controller** - Run controller tests only
**system** - Run system/integration tests only
**{path}** - Run specific test file

### Service-Specific Operations

By default, actions apply to all services. Use `service` parameter to target specific service:
- `web` - Rails application
- `db` - PostgreSQL
- `redis` - Redis cache
- `all` - All services (default)

## Examples

### Basic Operations

**Start development environment:**
```
Use managing-docker-development with action=start
```

**Stop all services:**
```
Use managing-docker-development with action=stop
```

**Restart specific service:**
```
Use managing-docker-development with action=restart service=web
```

**Rebuild everything:**
```
Use managing-docker-development with action=rebuild
```

### Development Tools

**Open Rails console:**
```
Use managing-docker-development with action=console
```

**Open bash shell:**
```
Use managing-docker-development with action=shell
```

**View Rails logs:**
```
Use managing-docker-development with action=logs service=web
```

**Check container status:**
```
Use managing-docker-development with action=ps
```

### Database Operations

**Run migrations:**
```
Use managing-docker-development with action=db db_action=migrate
```

**Rollback migration:**
```
Use managing-docker-development with action=db db_action=rollback
```

**Seed database:**
```
Use managing-docker-development with action=db db_action=seed
```

**Reset database:**
```
Use managing-docker-development with action=db db_action=reset
```

### Testing

**Run all tests:**
```
Use managing-docker-development with action=test test_path=all
```

**Run model tests:**
```
Use managing-docker-development with action=test test_path=model
```

**Run specific test:**
```
Use managing-docker-development with action=test test_path=test/models/user_test.rb
```

### RAG Operations

**Check RAG health:**
```
Use managing-docker-development with action=rag rag_action=health
```

**Verify RAG setup:**
```
Use managing-docker-development with action=rag rag_action=verify
```

**Seed system RAG stores:**
```
Use managing-docker-development with action=rag rag_action=seed
```

**List RAG stores:**
```
Use managing-docker-development with action=rag rag_action=list
```

**Test RAG functionality:**
```
Use managing-docker-development with action=rag rag_action=test
```

### Maintenance

**Clean up Docker resources:**
```
Use managing-docker-development with action=clean
```

## Resources

- [Docker Compose Reference](resources/docker-compose-commands.md) - All docker-compose commands
- [RAG Setup Guide](resources/rag-setup.md) - RAG system configuration
- [Troubleshooting](resources/troubleshooting.md) - Common Docker issues

## Resources

- [Docker Commands Reference](resources/docker-commands.md) - Complete Docker and docker-compose command guide
