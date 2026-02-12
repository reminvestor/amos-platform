# Secret Scanning with GitLeaks

AMOS Platform uses GitLeaks to prevent accidental commits of API keys, credentials, and other sensitive information to the repository.

## Overview

**GitLeaks** scans your code for secrets using pattern matching and entropy analysis. It runs in two places:

1. **GitHub Actions** - Automated scanning on every PR and push
2. **Pre-commit hooks** - Local scanning before you commit

## GitHub Actions (Automated)

The [GitLeaks workflow](../.github/workflows/gitleaks.yml) runs automatically on:
- Pull requests to `main`, `prod`, `dev`
- Pushes to `main`, `prod`, `dev`

**If secrets are detected:**
- ✅ The PR check will fail
- 📊 A SARIF report is uploaded to GitHub Security tab
- 🔍 Review the findings in the GitHub Actions logs

**To fix:**
1. Remove the secret from the code
2. Add legitimate false positives to `.gitleaks.toml`
3. Rotate any exposed credentials immediately

## Pre-commit Hooks (Local)

Install pre-commit hooks to catch secrets before they reach GitHub:

### Installation

```bash
# Install pre-commit (one-time setup)
pip install pre-commit

# Install the hooks
pre-commit install

# Test the setup
pre-commit run --all-files
```

### Usage

Once installed, pre-commit runs automatically when you commit:

```bash
git add .
git commit -m "My changes"

# GitLeaks runs automatically and blocks commit if secrets found
```

**Manual scan:**
```bash
# Scan all files
pre-commit run --all-files

# Scan specific file
pre-commit run --files app/services/my_service.rb

# Skip pre-commit checks (NOT RECOMMENDED)
git commit -m "My changes" --no-verify
```

## Configuration

### GitLeaks Configuration (`.gitleaks.toml`)

Custom rules and allowlists are defined in [.gitleaks.toml](../.gitleaks.toml):

**Detected secrets:**
- AWS Access Keys and Secret Keys
- Anthropic API Keys
- Stripe API Keys
- OpenAI API Keys
- GitHub Personal Access Tokens
- JWT Tokens
- Private SSH Keys
- Database connection strings

**Allowlisted paths:**
- `.env.example` files
- Test fixtures and specs
- Seed files (demo data)
- Documentation examples

**Adding a false positive:**
```toml
# In .gitleaks.toml
[allowlist]
regexes = [
  '''your-false-positive-pattern'''
]
```

### Pre-commit Configuration (`.pre-commit-config.yaml`)

Additional checks beyond GitLeaks:
- ✅ Trailing whitespace removal
- ✅ End-of-file fixing
- ✅ YAML/JSON validation
- ✅ Merge conflict detection
- ✅ Large file detection (max 1MB)
- ✅ Private key detection
- ✅ Ruby linting (RuboCop)
- ✅ ERB template linting
- ✅ JavaScript/TypeScript linting
- ✅ Markdown linting

## Best Practices

### ✅ DO:
- Use `.env.example` for environment variable templates
- Store secrets in Rails encrypted credentials (`rails credentials:edit`)
- Use environment variables for sensitive data
- Add test/demo credentials to `.gitleaks.toml` allowlist
- Rotate credentials immediately if accidentally committed

### ❌ DON'T:
- Commit `.env` files with real credentials
- Hardcode API keys in source code
- Store secrets in comments
- Skip pre-commit checks with `--no-verify` unless absolutely necessary
- Ignore GitLeaks failures in CI

## Handling Secret Leaks

**If you accidentally commit a secret:**

1. **Remove from code immediately:**
   ```bash
   git reset HEAD~1  # Undo last commit
   # Remove the secret from files
   git add .
   git commit -m "Remove secret"
   ```

2. **Rotate the credential:**
   - AWS: Delete and create new access keys
   - API keys: Regenerate from provider dashboard
   - Database passwords: Update and redeploy

3. **If already pushed to GitHub:**
   ```bash
   # Remove from history (DANGEROUS - coordinate with team)
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch path/to/file" \
     --prune-empty --tag-name-filter cat -- --all

   git push origin --force --all
   ```

4. **Report to security team** if the secret was in a public repository

## Testing GitLeaks

### Test locally:
```bash
# Install gitleaks CLI
brew install gitleaks  # macOS
# or
docker pull zricethezav/gitleaks:latest

# Run scan
gitleaks detect -v

# Scan with custom config
gitleaks detect -c .gitleaks.toml -v
```

### Test specific commit:
```bash
gitleaks detect --log-opts="HEAD~1..HEAD"
```

### Test uncommitted changes:
```bash
gitleaks protect -v
```

## GitHub Security Integration

GitLeaks results appear in:
- **Pull Request checks** - Status check pass/fail
- **Security tab** - Code scanning alerts (if SARIF upload enabled)
- **Actions logs** - Detailed findings

**View results:**
1. Go to repository → Security tab → Code scanning alerts
2. Filter by "GitLeaks" category
3. Review and dismiss false positives

## Troubleshooting

**Pre-commit hook not running:**
```bash
# Reinstall hooks
pre-commit uninstall
pre-commit install
```

**GitLeaks blocking valid code:**
Add to `.gitleaks.toml` allowlist:
```toml
[allowlist]
paths = [
  '''path/to/file\.rb$'''
]
```

**Update GitLeaks version:**
```bash
# Update pre-commit dependencies
pre-commit autoupdate

# Or manually edit .pre-commit-config.yaml
# Change rev: v8.18.2 to newer version
```

## References

- [GitLeaks Documentation](https://github.com/gitleaks/gitleaks)
- [Pre-commit Documentation](https://pre-commit.com/)
- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)

## Questions?

Contact the security team or open an issue in the repository.
