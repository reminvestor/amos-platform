# Contributing to AMOS

Welcome! AMOS is an open-source AI automation platform where **contributors are owners**. When you contribute, you earn AMOS tokens that represent real ownership in the platform.

---

## Quick Start

### 1. Fork & Clone
```bash
git clone https://github.com/YOUR_USERNAME/agent_marketing.git
cd agent_marketing
```

### 2. Setup
```bash
cp .env.example .env
# Edit .env with your API keys

docker-compose up -d  # Start Postgres, Redis
bundle install
rails db:create db:migrate db:seed
rails s
```

### 3. Make Changes
```bash
git checkout -b feature/your-feature-name
# Make your changes
git commit -m "feat: add awesome feature"
git push origin feature/your-feature-name
```

### 4. Submit PR
Open a Pull Request against `main`. Describe what you did and why.

---

## How You Get Paid (In Ownership)

Every approved contribution earns AMOS tokens. This isn't play money—it's real ownership:

| Contribution Type | Typical Tokens | Revenue Share | Governance |
|-------------------|----------------|---------------|------------|
| Major Feature | ~500 AMOS | ✅ | ✅ |
| Bug Fix | ~100 AMOS | ✅ | ✅ |
| Security Fix | ~300 AMOS | ✅ | ✅ |
| Documentation | ~50 AMOS | ✅ | ✅ |
| Code Review | ~25 AMOS | ✅ | ✅ |

**What this means:**
- 50% of platform revenue goes to token holders
- Your tokens = your share of that 50%
- You can vote on platform decisions
- You can trade tokens on crypto exchanges

Read the [Token Whitepaper](docs/whitepaper_simple.md) for full details.

---

## Contribution Process

### 1. Find Something to Work On

- Check [Issues](../../issues) for open tasks
- Look for `good first issue` label for beginner-friendly tasks
- Look for `help wanted` for priority items
- Or propose your own improvement

### 2. Claim It

Comment on the issue: "I'd like to work on this"

This prevents duplicate work and lets us assign appropriate token rewards.

### 3. Build It

Follow our coding standards (below). Ask questions in the issue if stuck.

### 4. Submit PR

- Clear description of what changed
- Link to the issue
- Screenshots for UI changes
- Tests for new features

### 5. Review & Merge

We'll review within 48 hours (usually faster). Once merged:
- Tokens credited to your account
- You're now an owner 🎉

---

## Coding Standards

### Ruby/Rails

```ruby
# Use descriptive names
def calculate_user_ownership_percentage(user)
  # ...
end

# Document public methods
# @param user [User] The user to check
# @return [Float] Ownership percentage (0-100)
def calculate_user_ownership_percentage(user)
  # ...
end

# Prefer early returns
def process_payment(payment)
  return unless payment.valid?
  return if payment.already_processed?
  
  # Main logic here
end
```

### JavaScript

```javascript
// Use const/let, never var
const config = loadConfig();
let counter = 0;

// Use async/await over .then()
async function fetchData() {
  const response = await fetch('/api/data');
  return response.json();
}
```

### Git Commits

Use conventional commits:

```
feat: add token claiming to wallet
fix: correct decay calculation for leap years
docs: update contribution guide
refactor: simplify reward calculator
test: add tests for governance voting
```

### Tests

- Write tests for new features
- Maintain or improve coverage
- Run tests before submitting: `rails test`

---

## Architecture Overview

```
app/
├── controllers/     # HTTP request handling
├── models/          # Data models & business logic
├── services/        # Complex business operations
├── jobs/            # Background processing
├── views/           # UI templates
└── javascript/      # Frontend JS

Key Services:
├── TokenEconomyService      # Token rewards & decay
├── ContributionRewardCalculator  # Calculate token amounts
├── RevenueShareService      # Distribute revenue
└── SolanaTokenService       # Blockchain integration
```

See [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) for full details.

---

## Token Economy Basics

Understanding the token economy helps you understand why your contributions matter:

1. **Fixed Supply**: 100M AMOS tokens, ever
2. **Earn or Buy**: Tokens can be earned OR purchased, but decay means passive buyers transfer stake to active contributors over time
3. **Decay**: Inactive stakes shrink (but floor protects 25%)
4. **Revenue Share**: 50% of platform revenue to holders
5. **Governance**: Vote on platform decisions

This means:
- Early contributors get more (halving schedule)
- Active contributors maintain stake
- Everyone plays by same rules

---

## Getting Help

- **Discord**: [Join our community](#) (link TBD)
- **Issues**: Open a GitHub issue
- **Email**: contribute@amoslabs.io

---

## Code of Conduct

Be excellent to each other. We're building something together.

- Be respectful and inclusive
- Assume good intent
- Give constructive feedback
- Help newcomers

Harassment, discrimination, or toxicity will result in removal from the project.

---

## License

By contributing, you agree that your contributions will be licensed under the [Apache 2.0 License](LICENSE).

---

## Recognition

All contributors are listed in [CONTRIBUTORS.md](CONTRIBUTORS.md) (created after first external contribution).

Major contributors are highlighted in release notes and may be invited to the Steward Council.

---

**Thank you for building the future of distributed AI ownership with us!** 🚀
