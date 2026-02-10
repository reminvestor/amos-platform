Run the AMOS complementary security scanner that covers vulnerability classes Shannon (DAST) does not test.

This scanner checks for:
- **Dependency vulnerabilities**: CVEs in Ruby gems (bundler-audit) and JS packages (yarn audit)
- **Static analysis**: Brakeman SAST for code-level security issues
- **Security headers**: X-Frame-Options, CSP, HSTS, X-Content-Type-Options, etc.
- **HTTP verb tampering**: TRACE/TRACK method exposure on sensitive endpoints
- **CORS policy**: Validates untrusted origins are rejected
- **Error info leakage**: Stack traces, version info in error pages
- **WebSocket security**: ActionCable authentication and origin restrictions

## Instructions

1. Run `bin/security-scan` with the appropriate argument based on what the user wants:
   - `bin/security-scan full` — Run all checks (default)
   - `bin/security-scan deps` — Dependency audit only
   - `bin/security-scan sast` — Brakeman static analysis only
   - `bin/security-scan headers` — Security headers check (needs running app)
   - `bin/security-scan verbs` — HTTP verb tampering check (needs running app)
   - `bin/security-scan cors` — CORS policy validation (needs running app)
   - `bin/security-scan errors` — Error information leakage (needs running app)
   - `bin/security-scan websocket` — WebSocket/ActionCable security check

2. If the user provides an argument like `$ARGUMENTS`, pass it to the script: `bin/security-scan $ARGUMENTS`

3. For live checks (headers, verbs, cors, errors), the app must be running. If not, suggest: `docker compose up -d` first.

4. Present the results clearly, highlighting any FAIL items and suggesting fixes.

5. If critical issues are found, also suggest running the full Shannon pentest for dynamic validation:
   ```
   cd shannon && ./shannon start URL=http://host.docker.internal:3000 REPO=amos-platform
   ```
