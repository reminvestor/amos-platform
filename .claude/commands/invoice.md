# Invoice Generator - Generate Invoice from Git History

Generate an invoice based on git commit history for a specified month.

## Arguments
- `$ARGUMENTS` - Format: `[month] [hourly_rate]`
  - **month**: Optional. Month to invoice (e.g., "december 2025", "2025-12", "last month"). Defaults to previous month.
  - **hourly_rate**: Required. Your hourly rate in dollars (e.g., "150" for $150/hr)

Examples:
- `/invoice 150` - Last month at $150/hr
- `/invoice december 2025 150` - December 2025 at $150/hr
- `/invoice 2025-11 125` - November 2025 at $125/hr

## Instructions

Execute the following workflow to generate an invoice:

### 1. Parse Arguments and Determine Date Range

Parse `$ARGUMENTS` to determine the month:
- If empty or "last month": Use the previous calendar month
- If month name + year (e.g., "december 2025"): Use that month
- If YYYY-MM format: Use that month

Calculate:
- `START_DATE`: First day of the month (YYYY-MM-01)
- `END_DATE`: Last day of the month (YYYY-MM-31 or appropriate)

### 2. Parse Rate and Load Configuration

Extract the hourly rate from `$ARGUMENTS` (the last number in the arguments).

If no rate provided, **ask the user** for their hourly rate.

**Default client: AMOS Labs**

**Load configuration** (check in order):
1. `~/.config/smilewise/invoice-config.local.json` (preferred - outside repo)
2. `.claude/invoice-config.local.json` (fallback - gitignored)

Settings from config:
- Include pipeline/DevOps work by default
- Max 10 hours per day
- Minimum 2 hours for any weekday between first and last commit

### 3. Analyze Git History

**IMPORTANT**: Always filter by author to ensure only the user's work is captured.

First, identify the git author name:
```bash
# Get the configured git user name
git config user.name
```

Run git log analysis for the date range, filtered by author:
```bash
# IMPORTANT: Use --all to include unmerged feature branches
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%ad %s" --date=format:"%Y-%m-%d %H:%M"
```

**Note**:
- Use `--author` flag on ALL git log commands throughout this workflow to ensure accurate work attribution.
- Use `--all` flag to capture work on unmerged feature branches (critical for accurate billing).

### 3b. Extract GitHub References

Extract GitHub issue and PR numbers from commit messages:
```bash
# Find GitHub issues/PRs referenced in commits (patterns: #123, fixes #123, closes #123)
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%s" | grep -oE '#[0-9]+' | sort -u
```

**GitHub Patterns to Match:**
- `#123` - Standard issue/PR reference
- `fixes #123` / `closes #123` - Issue closing keywords
- `Merge pull request #123` - PR merge commits
- `(#123)` - Parenthetical references (common in conventional commits)

### 3c. Check Unmerged Branches and PRs (Critical)

**IMPORTANT**: Always check for work on unmerged feature branches - this is billable work even if not yet merged to main/dev.

```bash
# Find all branches with commits in the billing period
echo "=== Branches with work in billing period ==="
for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  count=$(git log "$branch" --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --oneline 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    lines=$(git log "$branch" --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --stat --format="" 2>/dev/null | grep -E "files? changed" | awk '{sum+=$4+$6} END {print sum}')
    echo "$branch: $count commits, ~$lines lines"
  fi
done

# Check for open PRs with work in the period
gh pr list --state open --author "@me" --json number,title,createdAt,headRefName
```

**Include all work from:**
- Merged PRs (captured via main/dev branch)
- Open/draft PRs (work done but not yet reviewed/merged)
- Feature branches without PRs (work in progress)
- Uncommitted work (ask user about any significant uncommitted changes)

### 3d. Deep Feature Analysis (Critical)

**IMPORTANT**: Standard commit prefix patterns often miss significant work. Perform deep analysis:

#### Expanded Commit Patterns
Search for ALL action verbs, not just standard prefixes:
```bash
# Standard patterns (always include --author flag)
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%s" | grep -iE "^(feat|fix|add|implement|test|ci|build|docs|refactor|perf|chore):"

# CRITICAL: Also search for these commonly missed patterns
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%s" | grep -iE "^(integrate|upgrade|migrate|switch|complete|wire|replace|enable|configure|setup|convert|overhaul)"
```

#### Large Commit Detection
Find commits with significant code changes that may indicate major features:
```bash
# Find commits with 100+ lines changed (major features)
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --stat --format="%h %s" | \
  awk '/^[a-f0-9]+ /{commit=$0} /files? changed/{if($4+$6>100) print commit}'

# Get detailed stats for largest commits
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --stat --format="%h %s%n" | head -100
```

#### Technology-Specific Searches
Search for technology migrations and integrations by keyword:
```bash
# Voice/Audio technologies
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --grep="eleven" --grep="labs" --grep="polly" --grep="deepgram" --grep="whisper" --grep="transcription" --grep="voice" --grep="speech" --format="%ad %s" --date=short

# AI/ML technologies
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --grep="gemini" --grep="claude" --grep="bedrock" --grep="openai" --grep="langchain" --grep="rag" --grep="embedding" --grep="vector" --format="%ad %s" --date=short

# Infrastructure technologies
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --grep="docker" --grep="kubernetes" --grep="redis" --grep="postgres" --grep="aws" --grep="pipeline" --format="%ad %s" --date=short

# Authentication/Security
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --grep="oauth" --grep="mfa" --grep="otp" --grep="jwt" --grep="auth" --grep="security" --format="%ad %s" --date=short

# Mobile/Frontend
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --grep="flutter" --grep="react" --grep="mobile" --grep="ios" --grep="android" --format="%ad %s" --date=short
```

**Note**: Multiple `--grep` flags use OR logic by default. Use `--all-match` if you need AND logic.

#### Full Commit Body Analysis
For significant commits, read the full commit message (not just title):
```bash
# Get full commit messages for commits with 50+ lines changed
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --stat --format="=== %h ===%n%B" | \
  awk '/^=== /{commit=$0; body=""} !/^===/{body=body"\n"$0} /files? changed/{if($4+$6>50) print commit body}'
```

#### Test Coverage Analysis
Find test-related commits to understand feature scope:
```bash
# Find commits that added tests (indicates significant features)
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --stat --format="%s" -- "*_test.rb" "test_*.rb" "*_spec.rb" | head -50

# Count total tests added in period (for test frameworks)
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%s" | grep -iE "test|spec" | wc -l
```

**Verification Step**: After analysis, ask the user:
"I found [X] major features. Were there any significant technology changes, migrations, or integrations this month that I should verify are captured?"

### 4. Calculate Work Hours

**IMPORTANT**: Assume work was done on ALL weekdays (Monday-Friday) between the first and last commit dates, not just days with commits.

**Steps:**
1. Find the first and last commit dates in the period
2. Calculate all weekdays (Mon-Fri) between those dates (inclusive)
3. This is the "Days Worked" count
4. Allocate hours based on commit activity density:
   - Days with heavy commits (5+): 8-10 hours
   - Days with moderate commits (2-4): 6-8 hours
   - Days with light commits (1): 4-6 hours
   - Days with no commits but between active dates: 2-4 hours (minimum billable)

```bash
# Get first and last commit dates
FIRST_DATE=$(git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%ad" --date=short | sort | head -1)
LAST_DATE=$(git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%ad" --date=short | sort | tail -1)

# Count weekdays between dates (macOS)
python3 -c "
from datetime import datetime, timedelta
start = datetime.strptime('$FIRST_DATE', '%Y-%m-%d')
end = datetime.strptime('$LAST_DATE', '%Y-%m-%d')
weekdays = sum(1 for d in range((end - start).days + 1) if (start + timedelta(d)).weekday() < 5)
print(f'Weekdays worked: {weekdays}')
"
```

Apply exclusions if `include_pipeline_work` is false:
- Filter out commits matching exclude_patterns

### 5. Generate Work Summary

Create a detailed breakdown:
- Total commits
- Days worked
- Hours by category
- Major features/fixes delivered

### 6. Generate Line Items from Git History

Analyze commits to create detailed line items:
1. Group commits by category (feat, fix, refactor, test, docs, etc.)
2. Extract major features/PRs as individual line items
3. Allocate hours proportionally based on commit activity
4. **Extract date ranges for each category** using git log with date filtering

**Line Item Categories:**
- **Feature Development**: New functionality (prefix: `feat:`, `feature:`, `add:`, `implement:`, `integrate:`, `upgrade:`, `migrate:`, `switch:`, `complete:`, `wire:`, `replace:`, `enable:`)
- **Bug Fixes**: Issue resolution (prefix: `fix:`, `bugfix:`)
- **Testing**: Test coverage (prefix: `test:`)
- **Infrastructure**: DevOps/CI/CD (prefix: `ci:`, `build:`, `deploy:`, `pipeline:`, `perf:`, `configure:`, `setup:`)

**Extract Date Ranges Per Category:**
```bash
# Get date range for features (include expanded patterns)
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%ad %s" --date=short | \
  grep -iE "^[0-9].*(feat|add|implement|integrate|upgrade|migrate|complete)" | sort | \
  awk 'NR==1{first=$1} END{print first, $1}'

# Get date range for bug fixes
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%ad %s" --date=short | \
  grep -iE "^[0-9].*fix" | sort | awk 'NR==1{first=$1} END{print first, $1}'

# Get date range for testing
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%ad %s" --date=short | \
  grep -iE "^[0-9].*test" | sort | awk 'NR==1{first=$1} END{print first, $1}'

# Get date range for infrastructure
git log --all --author="$AUTHOR_NAME" --since="$START_DATE" --until="$END_DATE" --format="%ad %s" --date=short | \
  grep -iE "^[0-9].*(ci|pipeline|deploy|docker|build|perf|configure|setup)" | sort | \
  awk 'NR==1{first=$1} END{print first, $1}'
```

For each category with work:
- Calculate hours based on commit count and time span
- Create descriptive line item with specific deliverables
- **Include date range in line item name** (e.g., "Feature Development - December 2025 (Dec 3-23)")

### 7. Calculate Invoice Total

```
Sum of all line item amounts = Invoice Total
```

### 8. Output Invoice Data

Display:
```
═══════════════════════════════════════════════════════════════
                    INVOICE SUMMARY
═══════════════════════════════════════════════════════════════

Client: [Client Name]
Period: [Month Year]
Generated: [Current Date]

───────────────────────────────────────────────────────────────
WORK SUMMARY
───────────────────────────────────────────────────────────────

Days Worked:        [X] days
Total Commits:      [X] commits
PRs Merged:         [X] PRs

───────────────────────────────────────────────────────────────
LINE ITEMS (Based on Git History)
───────────────────────────────────────────────────────────────

1. Feature Development - [Month Year] ([date range])    [X] hrs × $[rate] = $[amount]
   • [Feature 1 description] (#123)
   • [Feature 2 description] (#124, #125)
   • [Feature 3 description] (#126)

2. Bug Fixes & Issue Resolution ([date range])          [X] hrs × $[rate] = $[amount]
   • [Fix 1 description] (#127)
   • [Fix 2 description] (#128)

3. Testing & Quality Assurance ([date range])           [X] hrs × $[rate] = $[amount]
   • [Test work description] (#129)

4. Infrastructure & DevOps ([date range])               [X] hrs × $[rate] = $[amount]
   • [DevOps work description] (#130)

───────────────────────────────────────────────────────────────
GITHUB REFERENCE
───────────────────────────────────────────────────────────────
Repository: https://github.com/NuvolaNetworks/agent_marketing
Issues/PRs: #123, #124, #125, #126, #127, #128, #129, #130

───────────────────────────────────────────────────────────────
INVOICE TOTALS
───────────────────────────────────────────────────────────────

Total Hours:        [X] hrs
Rate:               $[X]/hr
───────────────────────────────────────────────────────────────
TOTAL:              $[X,XXX.XX]
═══════════════════════════════════════════════════════════════
```

### 9. Offer Next Steps

Ask user:
1. **Create Zoho Invoice**: If Zoho credentials configured, offer to create invoice via API
2. **Export to CSV**: Save work log as CSV for manual import
3. **Adjust Hours**: Allow manual adjustment of calculated hours
4. **Save Config**: Save client details for future invoices

### 10. Create Zoho Draft Invoice (Optional)

If user chooses to create Zoho invoice, check credentials first:

#### 10a. Check/Refresh Zoho Token

**First-time setup** (if no refresh_token in config):
```bash
python scripts/zoho-oauth-setup.py
```
This opens a browser for one-time OAuth authorization and saves the refresh_token.

**Token refresh** (automatic when refresh_token exists):
```bash
# Get new access token using refresh token
curl -X POST "https://accounts.zoho.com/oauth/v2/token" \
  -d "grant_type=refresh_token" \
  -d "client_id=$CLIENT_ID" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "refresh_token=$REFRESH_TOKEN"
```

Extract `access_token` from response and use for API calls.

#### 10b. Create Draft Invoice

Generate line items from git history categories.

**Important**:
- Set `reference_number` to "[Month Year] Invoice" (e.g., "December 2025 Invoice")
- Set `date` to TODAY (when invoice is created/sent), NOT the billing period end date
- Set `due_date` to 15 days from invoice date (NET 15)
- Include approximate date ranges in line item names (e.g., "Feature Development - December 2025 (Dec 3-23)")

```bash
curl -X POST "https://www.zohoapis.com/invoice/v3/invoices?organization_id=$ORG_ID&send=false" \
  -H "Authorization: Zoho-oauthtoken $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "$CLIENT_ID",
    "reference_number": "[Month Year] Invoice",
    "date": "[TODAY - when invoice is sent]",
    "payment_terms": 15,
    "due_date": "[TODAY + 15 days]",
    "is_draft": true,
    "terms": "Payment due within 15 days (NET 15).",
    "line_items": [
      {
        "name": "Feature Development - [Month Year] ([date range])",
        "description": "• [Feature 1] (#123)\n• [Feature 2] (#124)\n• [Feature 3] (#125)\n\nGitHub: https://github.com/NuvolaNetworks/agent_marketing",
        "quantity": [FEATURE_HOURS],
        "rate": [HOURLY_RATE]
      },
      {
        "name": "Bug Fixes & Issue Resolution ([date range])",
        "description": "• [Fix 1] (#126)\n• [Fix 2] (#127)\n\nGitHub: https://github.com/NuvolaNetworks/agent_marketing",
        "quantity": [FIX_HOURS],
        "rate": [HOURLY_RATE]
      },
      {
        "name": "Testing & Quality Assurance ([date range])",
        "description": "• [Test work summary] (#128)\n\nGitHub: https://github.com/NuvolaNetworks/agent_marketing",
        "quantity": [TEST_HOURS],
        "rate": [HOURLY_RATE]
      },
      {
        "name": "Infrastructure & DevOps ([date range])",
        "description": "• [DevOps work summary] (#129)\n\nGitHub: https://github.com/NuvolaNetworks/agent_marketing",
        "quantity": [INFRA_HOURS],
        "rate": [HOURLY_RATE]
      }
    ]
  }'
```

**Note:**
- Only include line items that have work (hours > 0)
- Invoice is created as draft only - user must manually review and send from Zoho
- Line item descriptions are extracted from actual git commit messages

### Error Handling

- If no commits found: Report "No work found for this period"
- If Zoho API fails: Save invoice data locally and report error
- If git not available: Report error
