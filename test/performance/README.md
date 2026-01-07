# API Performance Tests

Comprehensive performance tests for the AMOS API (web + mobile) using [k6](https://k6.io/).

## Installation

```bash
# macOS
brew install k6

# Linux
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update
sudo apt-get install k6

# Docker
docker run --rm -i grafana/k6 run - <test.js
```

## Test Suite Overview

| Test File | Purpose | Duration | VUs | Safe |
|-----------|---------|----------|-----|------|
| `api_smoke_test.js` | Quick verification all endpoints work | 30s | 1 | Yes |
| `api_load_test.js` | Normal load testing | 4min | 20 | Yes |
| `api_stress_test.js` | Find breaking point | 17min | 150 | Yes |
| `api_full_coverage_test.js` | All endpoints coverage | 5min | 10 | Yes |
| `api_crud_test.js` | Create/Update/Delete ops | 1min | 1 | **No** (modifies data) |

## API Endpoints Covered

### Mobile API (v1)
- **Auth**: `/api/auth/login`, `/api/auth/me`, `/api/auth/logout`
- **Agents**: `GET /api/v1/agents`, `GET /api/v1/agents/:id`, `POST /api/v1/agents/:id/execute`
- **Campaigns**: Full CRUD + `/pause`, `/resume`
- **Contacts**: Full CRUD
- **Landing Pages**: Full CRUD + `/publish`, `/unpublish`
- **Tasks**: Full CRUD
- **Chat**: `/api/v1/chat/history`, `/api/v1/chat/conversations`
- **Voice**: `/api/voice/sessions`, `/api/voice/health/*`

### Web API
- **Scout Chat**: `POST /scout/chat`, `POST /scout/chat_stream`
- **Health**: `/health`, `/api/v1/health`

## Running Tests

### Prerequisites
```bash
# Start the backend
docker compose up -d
# OR
bin/dev
```

### Quick Commands

```bash
# Smoke test (30 seconds, 1 user)
k6 run test/performance/api_smoke_test.js

# Full coverage test (recommended)
k6 run test/performance/api_full_coverage_test.js

# Load test
k6 run test/performance/api_load_test.js

# Stress test (17 minutes)
k6 run test/performance/api_stress_test.js

# CRUD test (creates/deletes test data)
k6 run test/performance/api_crud_test.js
```

### With Custom Settings

```bash
# Different environment
k6 run -e BASE_URL=https://staging.example.com test/performance/api_full_coverage_test.js

# Custom credentials
k6 run -e TEST_EMAIL=user@example.com -e TEST_PASSWORD=secret123 test/performance/api_smoke_test.js

# Export results to JSON
k6 run --out json=results.json test/performance/api_load_test.js

# Run with more VUs
k6 run --vus 50 --duration 5m test/performance/api_load_test.js
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_URL` | `http://localhost:3000` | API base URL |
| `TEST_EMAIL` | `test@example.com` | Test user email |
| `TEST_PASSWORD` | `password123` | Test user password |

## Performance Thresholds

### Full Coverage Test
| Metric | Threshold | Description |
|--------|-----------|-------------|
| `http_req_duration` | p95 < 1000ms | Overall response time |
| `errors` | rate < 10% | Error rate |
| `auth_latency` | p95 < 300ms | Auth endpoints |
| `agents_latency` | p95 < 500ms | Agents API |
| `campaigns_latency` | p95 < 500ms | Campaigns API |
| `contacts_latency` | p95 < 500ms | Contacts API |
| `landing_pages_latency` | p95 < 500ms | Landing Pages API |
| `tasks_latency` | p95 < 500ms | Tasks API |
| `chat_latency` | p95 < 2000ms | Chat (allows streaming delay) |
| `voice_latency` | p95 < 500ms | Voice API |

### Stress Test
| Metric | Threshold | Description |
|--------|-----------|-------------|
| `http_req_duration` | p95 < 2000ms | Allow higher latency under stress |
| `errors` | rate < 30% | Higher threshold to find breaking point |

## Sample Output

```
╔══════════════════════════════════════════════════════════════╗
║            AMOS API FULL COVERAGE TEST RESULTS              ║
╠══════════════════════════════════════════════════════════════╣
║  Total Requests:         1234                          ║
║  Failed Requests:           5                          ║
║  Error Rate:            0.40%                         ║
╠══════════════════════════════════════════════════════════════╣
║  RESPONSE TIMES (ms)                                         ║
║    Average:            45.23                          ║
║    P90:                78.45                          ║
║    P95:               112.34                          ║
╠══════════════════════════════════════════════════════════════╣
║  ENDPOINT LATENCIES (P95 ms)                                 ║
║    Auth:               23.45                          ║
║    Agents:             67.89                          ║
║    Campaigns:          89.12                          ║
║    Contacts:           45.67                          ║
║    Landing Pages:      78.90                          ║
║    Tasks:              56.78                          ║
║    Chat:              234.56                          ║
║    Voice:              89.01                          ║
╚══════════════════════════════════════════════════════════════╝
```

## CI/CD Integration

### GitHub Actions
```yaml
name: Performance Tests

on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
  workflow_dispatch:

jobs:
  performance:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install k6
        run: |
          curl -s https://dl.k6.io/key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/k6.gpg
          echo "deb [signed-by=/etc/apt/keyrings/k6.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
          sudo apt-get update && sudo apt-get install k6

      - name: Start services
        run: docker compose up -d

      - name: Wait for services
        run: sleep 30

      - name: Run smoke test
        run: k6 run test/performance/api_smoke_test.js
        env:
          BASE_URL: http://localhost:3000
          TEST_EMAIL: ${{ secrets.TEST_EMAIL }}
          TEST_PASSWORD: ${{ secrets.TEST_PASSWORD }}

      - name: Run full coverage test
        run: k6 run test/performance/api_full_coverage_test.js

      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: k6-results
          path: test/performance/results/
```

## Troubleshooting

### "Login failed" error
- Verify backend is running: `curl http://localhost:3000/health`
- Check test credentials are correct
- Ensure test user exists in database

### High error rates
- Check API logs: `docker compose logs app`
- Verify database connections
- Check for rate limiting

### Timeouts
- Increase k6 timeout: `k6 run --http-debug test.js`
- Check network connectivity
- Verify backend isn't overloaded
