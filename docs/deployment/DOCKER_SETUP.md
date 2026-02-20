# Container Setup for AMOS

This guide helps you run AMOS with Podman (or Docker) Compose, including Docling and multi-tenant RAG features.

## Prerequisites

- **Podman** (recommended): `brew install podman podman-compose` then `podman machine init && podman machine start`
- **Docker** (alternative): Docker Desktop installed ([download here](https://www.docker.com/products/docker-desktop)) - requires paid license for commercial use
- `.env` file with credentials (AWS, OpenAI, Pinecone)

## Quick Start

### 1. One-Command Setup
```bash
./podman-setup.sh
```

This script auto-detects Podman or Docker and will:
- Create `.env` from `.env.example` if needed
- Build OCI containers
- Start PostgreSQL and Redis
- Create and migrate database
- Seed initial data
- Check Docling installation

### 2. Start AMOS
```bash
podman compose up
```

AMOS will be available at: **http://localhost:3000**

### 3. Populate System RAG (Optional)
```bash
podman compose run --rm web rails rag:populate_system
```

This indexes Stripe, HubSpot, and Mailgun integration docs into the shared system RAG.

## Environment Variables

### Required (for core functionality)
```bash
# AWS Bedrock (for Claude AI)
AWS_REGION=us-east-1
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
```

### Required for RAG Features
```bash
# OpenAI (for embeddings)
OPENAI_API_KEY=sk-...

# Pinecone (for vector storage)
PINECONE_API_KEY=your_pinecone_key
PINECONE_ENVIRONMENT=us-east-1
```

### Optional
```bash
# Mailgun (for email campaigns)
MAILGUN_API_KEY=your_mailgun_key
MAILGUN_DOMAIN=your_domain

# Serper (for web search)
SERPER_API_KEY=your_serper_key

# Stripe (for subscriptions)
STRIPE_SECRET_KEY=sk_test_...
STRIPE_WEBHOOK_SECRET=whsec_...
```

## Container Services

### Services Included
- **web**: Rails application (port 3000)
- **db**: PostgreSQL 16 (port 5432)
- **redis**: Redis 7 (port 6379)

### Service Health Checks
All services have health checks to ensure proper startup order.

## Docling in Containers

The container image includes Python 3 and attempts to install Docling automatically.

### Check Docling Status
```bash
podman compose run --rm web rails docling:check
```

### If Docling Fails
Don't worry! The system gracefully falls back to standard document processing. Docling is optional.

**Why it might fail**:
- Container image size constraints
- Memory limitations
- Python package conflicts

**To force reinstall**:
```bash
podman compose run --rm web pip3 install --break-system-packages -r requirements.txt
```

## Common Commands

### Database
```bash
# Create and migrate
podman compose run --rm web rails db:create db:migrate

# Reset database
podman compose run --rm web rails db:reset

# Seed data
podman compose run --rm web rails db:seed

# Rails console
podman compose run --rm web rails console
```

### RAG Management
```bash
# Populate system RAG
podman compose run --rm web rails rag:populate_system

# List all RAG stores
podman compose run --rm web rails rag:list

# Check RAG health
podman compose run --rm web rails rag:health

# Test query
podman compose run --rm web rails rag:test_query[1,"Stripe","How do I create a customer?"]

# Check access for entity
podman compose run --rm web rails rag:check_access[1,1]
```

### Docling Testing
```bash
# Check installation
podman compose run --rm web rails docling:check

# Test with file (mount local file)
podman compose run --rm -v /path/to/file.pdf:/tmp/file.pdf web rails docling:test[/tmp/file.pdf]

# Compare Docling vs standard
podman compose run --rm -v /path/to/file.pdf:/tmp/file.pdf web rails docling:compare[/tmp/file.pdf]
```

### Container Management
```bash
# Start all services
podman compose up

# Start in background
podman compose up -d

# Stop all services
podman compose down

# View logs
podman compose logs -f web

# Rebuild after code changes
podman compose build web

# Restart web service
podman compose restart web
```

## Troubleshooting

### Port Already in Use
If port 3000, 5432, or 6379 is already in use:

**Option 1**: Stop the conflicting service
```bash
# Find process using port
lsof -ti:3000 | xargs kill -9
```

**Option 2**: Change ports in `compose.yaml`
```yaml
web:
  ports:
    - "3001:3000"  # Use 3001 instead
```

### Database Connection Issues
```bash
# Check if database is running
podman compose ps

# View database logs
podman compose logs db

# Restart database
podman compose restart db
```

### Docling Installation Failed
This is normal! The system will use standard processing automatically.

To verify fallback:
```bash
podman compose logs web | grep "Docling"
```

You should see: `📄 Using standard document processing (Docling not available)`

### Bundle Install Errors
```bash
# Clear bundle cache and rebuild
podman compose down -v
podman compose build --no-cache web
podman compose up
```

### Yarn Install Errors
```bash
# Clear node_modules and rebuild
podman compose down
podman volume rm agent_marketing_node_modules
podman compose build web
podman compose up
```

## Development Workflow

### Making Code Changes
1. Edit code on your host machine
2. Changes are automatically synced via volume mounts
3. Restart if needed: `podman compose restart web`

### Installing New Gems
```bash
# Add gem to Gemfile, then:
podman compose run --rm web bundle install
podman compose restart web
```

### Installing New NPM Packages
```bash
# Add package to package.json, then:
podman compose run --rm web yarn install
podman compose restart web
```

### Running Tests
```bash
# All tests
podman compose run --rm web rails test

# Specific test file
podman compose run --rm web rails test test/models/rag_store_test.rb

# RAG tests
podman compose run --rm web rails test test/models/rag_store_test.rb test/services/rag_store_service_test.rb
```

## Performance Notes

### First Startup
- **Build time**: 5-10 minutes (downloads images, installs dependencies)
- **Subsequent startups**: 30-60 seconds

### Memory Usage
- **Minimum**: 4 GB RAM
- **Recommended**: 8 GB RAM (for Docling)
- **With Docling processing**: 12 GB RAM

### Disk Space
- **Base image**: ~2 GB
- **With dependencies**: ~3.5 GB
- **With Docling**: ~4.5 GB

## Production Considerations

This container setup is for **development only**. For production:

1. Use separate production Containerfile
2. Don't mount volumes (bake code into image)
3. Use managed PostgreSQL/Redis
4. Set proper environment variables
5. Use production-grade web server (Puma with multiple workers)
6. Enable SSL/TLS
7. Set up log aggregation
8. Configure backups

See `PRODUCTION_READINESS.md` for full guide.

## Cleaning Up

### Remove Containers Only
```bash
podman compose down
```

### Remove Containers and Volumes
```bash
podman compose down -v
```

### Remove Everything (including images)
```bash
podman compose down -v --rmi all
```

## Getting Help

### Check Service Status
```bash
podman compose ps
```

### View Logs
```bash
# All services
podman compose logs

# Specific service
podman compose logs web

# Follow logs
podman compose logs -f web
```

### Shell Access
```bash
# Rails console
podman compose run --rm web rails console

# Bash shell
podman compose run --rm web bash

# Database shell
podman compose run --rm db psql -U postgres -d amos_development
```

## Feature Branch Specific

### Testing Multi-Tenant RAG

**Create test entities**:
```bash
podman compose run --rm web rails console

# In console:
entity1 = Entity.create!(name: "Test Company 1")
entity2 = Entity.create!(name: "Test Company 2")
```

**Create entity-specific RAG stores**:
```ruby
# In rails console
require 'rails_helper'

# Create entity 1's RAG store
processor = DocumentProcessorService.new
chunks = processor.process_documents([
  { type: 'text', content: 'Entity 1 private docs', metadata: { source: 'test' } }
])

service = RagStoreService.new
service.create_rag_store("PrivateAPI", chunks[:chunks], {
  store_type: 'entity',
  entity: entity1
})

# Create entity 2's RAG store
service.create_rag_store("SecretAPI", chunks[:chunks], {
  store_type: 'entity',
  entity: entity2
})
```

**Test isolation**:
```bash
# Check that entity 1 can't access entity 2's store
podman compose run --rm web rails rag:check_access[1,2]
# Should show: ❌ Access: DENIED
```

### Testing Docling

**Prepare test PDF**:
```bash
# Mount a local PDF file
podman compose run --rm -v /path/to/test.pdf:/tmp/test.pdf web rails docling:test[/tmp/test.pdf]
```

**Compare processing**:
```bash
podman compose run --rm -v /path/to/test.pdf:/tmp/test.pdf web rails docling:compare[/tmp/test.pdf]
```

---

**Last Updated**: 2026-02-19
**Container Engine**: Podman (recommended) or Docker
