# Docker Commands Reference

Quick reference for Docker and docker-compose operations.

## Container Management

### Starting and Stopping

```bash
# Start all services in background
docker-compose up -d

# Start and view logs
docker-compose up

# Stop all services
docker-compose down

# Stop and remove volumes (⚠️  destroys data)
docker-compose down -v

# Restart specific service
docker-compose restart web

# Restart all services
docker-compose restart
```

### Viewing Status

```bash
# List running containers
docker-compose ps

# View container details
docker-compose ps web

# Check container logs
docker-compose logs web

# Follow logs in real-time
docker-compose logs -f web

# View last 100 lines
docker-compose logs --tail=100 web

# View logs from specific time
docker-compose logs --since="2024-01-01T10:00:00" web
```

### Executing Commands

```bash
# Run command in new container
docker-compose run --rm web rails console

# Execute in running container
docker-compose exec web rails runner "puts User.count"

# Open bash shell
docker-compose exec web bash

# Run command as different user
docker-compose exec -u root web bash
```

## Building and Rebuilding

```bash
# Build images
docker-compose build

# Build without cache (fresh build)
docker-compose build --no-cache

# Build specific service
docker-compose build web

# Build and start
docker-compose up --build

# Pull latest images
docker-compose pull
```

## Database Operations

```bash
# Create database
docker-compose run --rm web rails db:create

# Run migrations
docker-compose run --rm web rails db:migrate

# Rollback migration
docker-compose run --rm web rails db:rollback

# Reset database (⚠️  destroys data)
docker-compose run --rm web rails db:drop db:create db:migrate

# Seed database
docker-compose run --rm web rails db:seed

# Database console
docker-compose exec db psql -U postgres -d amos_development
```

## Debugging

```bash
# View environment variables
docker-compose exec web env

# Check if port is bound
lsof -i :3000

# View disk usage
docker system df

# View detailed disk usage
docker system df -v

# Check container resource usage
docker stats

# Inspect container
docker inspect <container_id>

# View container diff (changed files)
docker diff <container_id>
```

## Cleaning Up

```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes
docker volume prune

# Remove unused networks
docker network prune

# Remove everything (⚠️  destroys data)
docker system prune -a --volumes

# Remove specific container
docker rm <container_id>

# Force remove running container
docker rm -f <container_id>

# Remove specific image
docker rmi <image_id>
```

## Volume Management

```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect amos_postgres_data

# Remove volume
docker volume rm amos_postgres_data

# Create volume
docker volume create amos_postgres_data

# Copy files from volume
docker cp <container_id>:/app/file.txt ./local-file.txt

# Copy files to container
docker cp ./local-file.txt <container_id>:/app/file.txt
```

## Network Operations

```bash
# List networks
docker network ls

# Inspect network
docker network inspect amos_default

# Connect container to network
docker network connect amos_default <container_id>

# Disconnect container from network
docker network disconnect amos_default <container_id>
```

## Performance and Monitoring

```bash
# View real-time resource usage
docker stats

# View resource usage for specific container
docker stats web

# View container processes
docker-compose top

# View detailed process information
docker-compose top web

# Check container health
docker inspect --format='{{.State.Health.Status}}' <container_id>
```

## Compose-Specific

```bash
# Validate docker-compose.yml
docker-compose config

# List all compose projects
docker-compose ls

# Scale services
docker-compose up --scale worker=3

# View service ports
docker-compose port web 3000

# Pause services
docker-compose pause

# Unpause services
docker-compose unpause

# Kill services (force stop)
docker-compose kill
```

## Common Workflows

### Fresh Start
```bash
# Stop everything, remove volumes, rebuild, start
docker-compose down -v
docker-compose build --no-cache
docker-compose up -d
docker-compose run --rm web rails db:create db:migrate db:seed
```

### Update After Pull
```bash
# Pull latest code, rebuild, restart
git pull
docker-compose build
docker-compose run --rm web rails db:migrate
docker-compose restart
```

### Debug Connection Issues
```bash
# Check container status
docker-compose ps

# Check logs for errors
docker-compose logs web | tail -50

# Restart container
docker-compose restart web

# Check network connectivity
docker-compose exec web ping db
```

### Database Backup
```bash
# Backup
docker-compose exec db pg_dump -U postgres amos_development > backup.sql

# Restore
docker-compose exec -T db psql -U postgres amos_development < backup.sql
```

## Dockerfile Tips

### Multi-Stage Builds
```dockerfile
# Build stage
FROM ruby:3.2 AS builder
WORKDIR /app
COPY Gemfile* ./
RUN bundle install

# Runtime stage
FROM ruby:3.2-slim
WORKDIR /app
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .
CMD ["rails", "server", "-b", "0.0.0.0"]
```

### Layer Caching
```dockerfile
# Cache dependencies separately from code
COPY Gemfile* ./
RUN bundle install

# Copy code last (changes frequently)
COPY . .
```

## Environment Variables

```bash
# Set in docker-compose.yml
services:
  web:
    environment:
      - RAILS_ENV=development
      - DATABASE_URL=postgresql://postgres:postgres@db/amos_development

# Or use .env file
env_file:
  - .env

# Override in command
docker-compose run --rm -e RAILS_ENV=test web rails test
```

## Troubleshooting

### Container Won't Start
```bash
# Check logs for error
docker-compose logs web

# Try running command manually
docker-compose run --rm web rails runner "puts 'test'"

# Check for port conflicts
lsof -i :3000

# Rebuild without cache
docker-compose build --no-cache web
```

### Database Connection Failed
```bash
# Check database container is running
docker-compose ps db

# Check database logs
docker-compose logs db

# Test connection
docker-compose exec web rails runner "ActiveRecord::Base.connection.execute('SELECT 1')"

# Recreate database container
docker-compose stop db
docker volume rm amos_postgres_data
docker-compose up -d db
docker-compose run --rm web rails db:create db:migrate
```

### Out of Disk Space
```bash
# Check usage
docker system df

# Clean up
docker system prune -a
docker volume prune

# Check host disk space
df -h
```

### Slow Performance
```bash
# Check resource limits
docker stats

# Increase Docker Desktop resources
# Preferences > Resources > Advanced

# Check for volume mount performance
# Use delegated mode in docker-compose.yml:
volumes:
  - .:/app:delegated
```

## Quick Reference Card

| Task | Command |
|------|---------|
| Start | `docker-compose up -d` |
| Stop | `docker-compose down` |
| Logs | `docker-compose logs -f web` |
| Shell | `docker-compose exec web bash` |
| Rails console | `docker-compose run --rm web rails console` |
| Run migrations | `docker-compose run --rm web rails db:migrate` |
| Rebuild | `docker-compose build` |
| Clean up | `docker system prune` |
| Fresh start | `docker-compose down -v && docker-compose up -d` |

## Resources

- [Docker Compose Docs](https://docs.docker.com/compose/)
- [Docker CLI Reference](https://docs.docker.com/engine/reference/commandline/cli/)
- Project `docker-compose.yml` for service definitions
- `.env` file for environment variables
