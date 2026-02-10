Run the Shannon AI pentester against the AMOS platform.

Shannon is a fully autonomous AI pentester that tests for:
- SQL/Command/Template injection
- Cross-site scripting (XSS)
- Broken authentication (JWT, session, MFA bypass)
- Broken authorization (IDOR, privilege escalation)
- Server-side request forgery (SSRF)

## Instructions

1. Check that Shannon is set up:
   - Verify `shannon/` directory exists. If not, run `bin/shannon-setup`.
   - Verify `shannon/.env` has a real `ANTHROPIC_API_KEY` (not the placeholder).

2. Check that Docker is running: `docker info`

3. Check that the AMOS app is running: `curl -s http://localhost:3000 > /dev/null && echo "App running" || echo "App not running"`
   - If not running, suggest: `docker compose up -d`

4. Based on user input (`$ARGUMENTS`), run Shannon:
   - Default (no args): `cd shannon && ./shannon start URL=http://host.docker.internal:3000 REPO=amos-platform CONFIG=./configs/amos-platform.yaml`
   - With custom args: `cd shannon && ./shannon start $ARGUMENTS`

5. After starting, show the user how to monitor:
   - `cd shannon && ./shannon logs` — Real-time logs
   - `cd shannon && ./shannon query ID=<workflow-id>` — Check progress
   - Open http://localhost:8233 — Temporal Web UI

6. Remind the user:
   - Runtime: ~1-1.5 hours
   - Cost: ~$50 per run (Claude API)
   - Only run against staging/dev, never production
