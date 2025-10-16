# Docker Setup Guide for AMOS

## Quick Start

### 1. Prerequisites
- Docker installed and running
- Docker Compose installed

### 2. Configure Environment Variables

Edit `.env` file and add your AWS Bedrock credentials:

```bash
AWS_ACCESS_KEY_ID=your_actual_aws_key
AWS_SECRET_ACCESS_KEY=your_actual_aws_secret
AWS_REGION=us-east-1
```

### 3. Start the Application

```bash
# Start all services (database, Redis, and web app)
docker-compose up

# Or run in background
docker-compose up -d

# View logs
docker-compose logs -f web
```

### 4. Access the Application

- **Application**: http://app.localhost:3000 (use `app.` subdomain!)
- **Marketing Site**: http://localhost:3000 (public landing page)
- **Database**: localhost:5432
- **Redis**: localhost:6379

⚠️ **Important**: The app uses subdomain routing. You must access the app at `app.localhost:3000` to sign in and use features. The root `localhost:3000` is the public marketing site.

### 5. Stop the Application

```bash
# Stop all containers
docker-compose down

# Stop and remove volumes (clears database)
docker-compose down -v
```

## Development Workflow

### Running Commands in the Container

```bash
# Rails console
docker-compose exec web rails console

# Run migrations
docker-compose exec web rails db:migrate

# Run tests
docker-compose exec web rails test

# Rebuild assets
docker-compose exec web yarn build
docker-compose exec web yarn build:css
```

### Database Management

```bash
# Create database
docker-compose exec web rails db:create

# Run migrations
docker-compose exec web rails db:migrate

# Seed database
docker-compose exec web rails db:seed

# Reset database (drop, create, migrate, seed)
docker-compose exec web rails db:reset
```

### Viewing Logs

```bash
# All services
docker-compose logs -f

# Just the web app
docker-compose logs -f web

# Just the database
docker-compose logs -f db
```

## Troubleshooting

### Asset Errors (Missing application.js)

If you see errors about missing `application.js`:

```bash
docker-compose exec web yarn build
docker-compose exec web yarn build:css
```

### Database Connection Issues

```bash
# Check if database is running
docker-compose ps

# Restart database
docker-compose restart db

# Check database logs
docker-compose logs db
```

### Port Already in Use

If port 3000, 5432, or 6379 is already in use:

1. Stop the conflicting service, or
2. Change the port mapping in `docker-compose.yml`:

```yaml
ports:
  - "3001:3000"  # Use port 3001 instead
```

### Rebuilding After Changes

If you've made changes to Gemfile or package.json:

```bash
# Rebuild the web container
docker-compose build web

# Restart with new build
docker-compose up --build web
```

### Clean Start

To completely reset everything:

```bash
# Stop and remove all containers, volumes, and images
docker-compose down -v
docker rmi agent_marketing-web

# Rebuild and start fresh
docker-compose up --build
```

## Containers Overview

### Database (db)
- **Image**: postgres:16-alpine
- **Port**: 5432
- **Volume**: postgres_data (persists data)
- **Health Check**: Checks if PostgreSQL is ready

### Redis (redis)
- **Image**: redis:7-alpine
- **Port**: 6379
- **Volume**: redis_data (persists data)
- **Health Check**: Checks if Redis responds to ping

### Web Application (web)
- **Build**: Custom Dockerfile.dev
- **Port**: 3000
- **Volumes**:
  - Application code (live-reloaded)
  - bundle_cache (speeds up gem installs)
  - node_modules (speeds up yarn installs)
- **Depends On**: db and redis must be healthy

## Environment Variables

The `.env` file contains all configuration. Required variables:

```bash
# Required - AWS Bedrock for AI
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret

# Auto-configured for Docker
DATABASE_URL=postgresql://postgres:postgres@db:5432/amos_development
REDIS_URL=redis://redis:6379/0

# Optional - External services
MAILGUN_API_KEY=
MAILGUN_DOMAIN=
OPENAI_API_KEY=
PINECONE_API_KEY=
PINECONE_ENVIRONMENT=
SERPER_API_KEY=
```

## Performance Notes

### First Run
- Building the Docker image takes ~5-10 minutes (downloads Ruby, Node, gems, etc.)
- Subsequent starts are much faster (images are cached)

### Code Changes
- Code changes are live-reloaded (no rebuild needed)
- Gemfile/package.json changes require rebuild: `docker-compose up --build`

### Volumes
- `bundle_cache` and `node_modules` volumes speed up dependency installs
- `postgres_data` and `redis_data` persist your database

## Production Deployment

This Docker setup is for **development only**. For production:

1. Use the production `Dockerfile` (multi-stage build)
2. Set `RAILS_ENV=production`
3. Use managed PostgreSQL (AWS RDS, etc.)
4. Use managed Redis (ElastiCache, etc.)
5. See [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md) for details

## Next Steps

Once the app is running:

1. **Create an account**: Visit http://localhost:3000
2. **Test the chat**: Try "Create a landing page"
3. **Configure integrations**: Add Stripe, HubSpot, etc. in settings
4. **Test workflows**: Landing pages, email campaigns, etc.

See [README.md](README.md) for more information about AMOS features.
