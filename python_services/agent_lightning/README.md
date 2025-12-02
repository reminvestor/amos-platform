# Agent Lightning Service

Python microservice for RL-based AI agent training using Microsoft's Agent Lightning library.

## Overview

This service provides real reinforcement learning-based training for AI agents. It receives trace data from the Rails application, converts it to Agent Lightning's Rollout format, and executes training with the VERL algorithm.

## Architecture

```
Rails Application (Data Collection)
        ↓
  REST API calls
        ↓
Agent Lightning Service (This)
    ├── FastAPI Server (port 4747)
    ├── LightningStoreServer (port 4748)
    ├── Store Adapter (Rails DB → Rollouts)
    ├── Trainer + VERL Algorithm
    └── Checkpoint Management
```

## Setup

### Local Development

```bash
# Install dependencies
pip install -r requirements.txt

# Copy environment template
cp .env.example .env

# Edit .env with your settings
nano .env

# Run the service
python app.py
```

### Docker

```bash
# Build image
docker build -t agent-lightning-service .

# Run container
docker run -p 4747:4747 -p 4748:4748 \
  -e DATABASE_URL=postgresql://... \
  -e RAILS_API_URL=http://host.docker.internal:3000 \
  agent-lightning-service
```

### With Docker Compose

The service is integrated into the main application's Docker Compose setup:

```bash
# Start all services including Agent Lightning
docker-compose up -d

# View logs
docker-compose logs -f agent_lightning

# Check health
curl http://localhost:4747/health
```

## API Endpoints

### Health Check
```
GET /health
```

Returns service status and Agent Lightning availability.

### Create Rollout
```
POST /api/rollouts
Content-Type: application/json

{
  "rollout_id": "uuid",
  "input": { "request_text": "..." },
  "metadata": { "workflow_id": 123 },
  "status": "queuing"
}
```

### Add Span
```
POST /api/spans
Content-Type: application/json

{
  "rollout_id": "uuid",
  "attempt_id": "uuid",
  "span": { ... }
}
```

### Start Training
```
POST /api/training/start
Content-Type: application/json

{
  "entity_id": 1,
  "config": {
    "learning_rate": 0.001,
    "batch_size": 32,
    "num_epochs": 3
  },
  "trace_ids": ["optional", "list"]
}
```

### Get Training Status
```
GET /api/training/{job_id}/status
```

### List Training Jobs
```
GET /api/training/jobs
```

## Configuration

All configuration is done via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | - | PostgreSQL connection string |
| `RAILS_API_URL` | `http://localhost:3000` | Rails application URL |
| `RAILS_API_KEY` | - | API authentication key |
| `AGENT_LIGHTNING_RUNNERS` | `4` | Number of concurrent workers |
| `AGENT_LIGHTNING_STRATEGY` | `cs` | Execution strategy (cs/sm) |
| `LOG_LEVEL` | `INFO` | Logging level |
| `DEBUG` | `false` | Enable debug mode |

## Development Phases

### ✅ Phase 1: Basic Service (Current)
- FastAPI server
- Health endpoints
- Docker integration
- Configuration management

### 🚧 Phase 2: Store Adapter (Next)
- PostgreSQL connection to Rails DB
- Trace → Rollout conversion
- Data validation

### 📋 Phase 3: Rails Integration
- Client library in Rails
- Span emission from workflows
- End-to-end data flow

### 📋 Phase 4: Trainer Integration
- VERL algorithm integration
- Training orchestration
- Checkpoint management

### 📋 Phase 5: Production Deployment
- Monitoring and alerting
- Error recovery
- Performance tuning

## Testing

```bash
# Run tests
pytest

# With coverage
pytest --cov=. --cov-report=html

# Integration tests
pytest tests/integration/
```

## Monitoring

The service exposes health and status endpoints for monitoring:

```bash
# Health check
curl http://localhost:4747/health

# Active training jobs
curl http://localhost:4747/api/training/jobs

# Specific job status
curl http://localhost:4747/api/training/{job_id}/status
```

## Troubleshooting

### Service won't start

Check that required environment variables are set:
```bash
docker-compose logs agent_lightning
```

### Agent Lightning not available

Ensure the Python package is installed:
```bash
pip list | grep agent-lightning
```

### Database connection errors

Verify DATABASE_URL and that PostgreSQL is accessible:
```bash
psql $DATABASE_URL -c "SELECT 1"
```

### Training jobs failing

Check logs for specific errors:
```bash
docker-compose logs -f agent_lightning | grep "ERROR"
```

## Further Reading

- [Agent Lightning Documentation](https://microsoft.github.io/agent-lightning/stable/)
- [Integration Architecture](../../docs/AGENT_LIGHTNING_REAL_INTEGRATION.md)
- [Rails Side Documentation](../../docs/AGENT_LIGHTNING_INTEGRATION.md)
