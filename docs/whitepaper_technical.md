# AMOS Token: Technical Whitepaper

**Version 2.0 | January 2026**

---

## Abstract

AMOS (Autonomous Marketing Operating System) Token is a Solana-based SPL token designed to align incentives between platform contributors, distributors, and users. Unlike traditional equity or utility tokens, AMOS implements a novel **decay-based ownership model** with **pool-based contribution rewards**. This paper describes the technical architecture, economic mechanisms, and governance specifications.

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Token Specifications](#2-token-specifications)
3. [Economic Model](#3-economic-model)
4. [Decay Mechanism](#4-decay-mechanism)
5. [Wealth Preservation](#5-wealth-preservation)
6. [Reward Calculation](#6-reward-calculation)
7. [Blockchain Integration](#7-blockchain-integration)
8. [Governance](#8-governance)
9. [Security Considerations](#9-security-considerations)
10. [Technical Implementation](#10-technical-implementation)

---

## 1. Introduction

### 1.1 Problem Statement

Traditional platform economics suffer from misaligned incentives:

- **Founders/VCs** capture most value through equity
- **Early contributors** are compensated in cash, missing long-term upside
- **Passive holders** accumulate without contributing
- **Late participants** face insurmountable barriers to meaningful ownership
- **USD-denominated rewards** create regulatory complexity and external dependencies

### 1.2 Solution

AMOS Token introduces:

1. **Contribution-based ownership** - Tokens earned, not bought
2. **Decay function** - Continuous participation required for maximum stake
3. **Pool-based rewards** - No external price dependencies
4. **Transparent distribution** - All ownership publicly verifiable on-chain
5. **Revenue sharing** - Token holders receive portion of platform revenue

### 1.3 Design Principles

- **Fairness**: Same rules for founders and contributors
- **Transparency**: All allocations on-chain and auditable
- **Sustainability**: Self-balancing economic mechanisms
- **Accessibility**: Low barriers to participation
- **Independence**: No USD denomination or external price dependencies

---

## 2. Token Specifications

### 2.1 Basic Parameters

| Parameter | Value |
|-----------|-------|
| **Name** | Amos Platform Token |
| **Symbol** | AMOS |
| **Network** | Solana |
| **Token Standard** | SPL Token |
| **Decimals** | 9 |
| **Total Supply** | 100,000,000 (fixed) |
| **Mint Authority** | Disabled (immutable) |

### 2.2 Initial Allocation

```
Total Supply: 100,000,000 AMOS

┌────────────────────────────────────────────────────────────┐
│  Treasury (60%)          │ 60,000,000 │ Ongoing rewards   │
│  Founding Pool (15%)     │ 15,000,000 │ Core team         │
│  Investor Pool (10%)     │ 10,000,000 │ Future investors  │
│  Community Pool (10%)    │ 10,000,000 │ Airdrops/grants   │
│  Reserve (5%)            │  5,000,000 │ Emergency/ops     │
└────────────────────────────────────────────────────────────┘
```

### 2.3 Immutability

- Mint authority disabled at genesis
- No additional tokens can ever be created
- Only mechanism to increase supply: None
- Only mechanism to decrease supply: Burn

---

## 3. Economic Model

### 3.1 Token Utility

1. **Revenue Share**: 40% of platform revenue distributed to holders
2. **Governance**: Voting rights on multiple proposal categories
3. **Platform Benefits**: Premium features for staked tokens
4. **Trading**: Freely tradeable on Solana DEXs (Jupiter, Raydium)

### 3.2 Revenue Allocation

```ruby
REVENUE_ALLOCATION = {
  token_holders: 0.40,    # Distributed proportionally
  operations: 0.30,       # Platform operations
  r_and_d: 0.20,          # Voted by token holders
  treasury: 0.10          # Future reserves
}
```

### 3.3 Value Accrual

Token value derives from:

1. **Revenue Rights**: Claim on 40% of platform revenue
2. **Scarcity**: Fixed supply with ongoing burns
3. **Utility**: Platform access and governance
4. **Network Effects**: Growing contributor/user base

---

## 4. Decay Mechanism

### 4.1 Rationale

Decay prevents:

- Passive accumulation without contribution
- Early whale domination
- Token hoarding and velocity reduction
- Governance capture

### 4.2 Decay Formula

For a stake with initial amount `I`, current amount `C`, and annual decay rate `r`:

```
Daily Decay = C × (r / 365)
New Amount = C - Daily Decay
```

But amount never falls below the **graduated decay floor**:

```
Floor = I × floor_percentage(tenure_years)
C_new = max(C - Daily Decay, Floor)
```

### 4.3 Tenure-Based Decay Reduction

Decay rate decreases with holding duration:

| Years Held | Annual Decay Rate |
|------------|-------------------|
| 0-2 | 40% |
| 2-5 | 25% |
| 5-10 | 15% |
| 10+ | 5% |

### 4.4 Decay Example

```
Initial stake: 10,000 AMOS
Year 0 floor: 500 AMOS (5%)
Year 5 floor: 2,500 AMOS (25%)

Year 0: 10,000 tokens
Year 1: 6,000 tokens (40% decay)
Year 2: 3,600 tokens (40% decay)
Year 3: 2,700 tokens (25% decay - tenure reduction)
Year 5: 2,500 tokens (floor reached)
Year 20: 2,500 tokens (permanent)
```

### 4.5 Decay Recycling

Decayed tokens are split:

- **10%**: Burned (deflationary)
- **90%**: Returned to treasury (re-circulation)

---

## 5. Wealth Preservation

### 5.1 Graduated Decay Floor

Floor percentage **grows with tenure** to prevent early adopters from locking in permanent advantages while still rewarding long-term commitment:

| Tenure | Floor % | Rationale |
|--------|---------|-----------|
| 0-1 year | 5% | Earn your security |
| 1-3 years | 10% | Building commitment |
| 3-5 years | 15% | Established contributor |
| 5+ years | 25% | Maximum security |

This enables:

- Generational wealth transfer (after tenure buildup)
- Long-term planning
- Fair treatment of late joiners

### 5.2 Staking Vaults

Lock tokens to reduce decay:

| Tier | Lock Period | Decay Reduction |
|------|-------------|-----------------|
| Bronze | 1 year | 25% |
| Silver | 3 years | 50% |
| Gold | 5 years | 75% |
| Permanent | 10 years | 100% (no decay) |

### 5.3 Inheritance

Stakes can be transferred to designated beneficiaries:

- Inherited stakes receive reduced decay (10% annual)
- Transfer requires KYC verification
- 2% burn on transfer (anti-abuse)

---

## 6. Reward Calculation

### 6.1 Pool-Based Relative Scoring

**No USD denomination.** Contributions are measured in internal points, and rewards come from a daily emission pool:

```
Your Tokens = (Your Points / Total Period Points) × Daily Emission Pool
```

This ensures:
- No dependency on external prices
- Collaborative distribution
- Self-balancing economics
- Simple to understand

### 6.2 Base Contribution Points

| Contribution Type | Base Points |
|-------------------|-------------|
| Feature (code) | 500 |
| Bug Fix | 100 |
| Security Fix | 300 |
| Documentation | 50 |
| Affiliate Sale | 200 |
| Enterprise Deal | 500 |
| Support Ticket | 25 |
| Content Creation | 50 |
| Tutorial | 150 |

### 6.3 Complexity Multipliers

| Level | Multiplier |
|-------|------------|
| 1 (Trivial) | 0.5x |
| 2 (Simple) | 0.75x |
| 3 (Standard) | 1.0x |
| 4 (Complex) | 1.5x |
| 5 (Exceptional) | 2.5x |

### 6.4 Halving Schedule

Daily emission pool decreases over time:

| Year | Multiplier | Daily Emission |
|------|------------|----------------|
| 0-2 | 1.0x | ~16,000 AMOS |
| 2-4 | 0.5x | ~8,000 AMOS |
| 4-6 | 0.25x | ~4,000 AMOS |
| 6-8 | 0.125x | ~2,000 AMOS |
| 8+ | 0.0625x | ~1,000 AMOS |

### 6.5 Success Multipliers (Rewarding Growth)

When the platform succeeds (token price rises), contributors are **rewarded more**, not less:

| Success Band | Price Range | Multiplier | Rationale |
|--------------|-------------|------------|-----------|
| Struggling | <$0.01 | 1.0x | Baseline protection |
| Building | $0.01-$0.05 | 1.1x | Slight boost |
| Growing | $0.05-$0.20 | 1.25x | Success bonus |
| Thriving | $0.20-$0.50 | 1.5x | Share the success! |
| Soaring | >$0.50 | 2.0x | Big success = big rewards |

### 6.6 Complete Reward Formula

```ruby
points = base_points × complexity_mult × halving_mult × success_mult
tokens = points × point_to_token_ratio

# With bounds
tokens = clamp(tokens, MIN_TOKENS, MAX_TOKENS)
```

---

## 7. Blockchain Integration

### 7.1 Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  AMOS Platform (Off-Chain)                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │ TokenStake  │  │ Contribution│  │ Decay Engine        │ │
│  │ (Internal)  │  │ Tracking    │  │ (Daily Job)         │ │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘ │
└─────────┼────────────────┼────────────────────┼─────────────┘
          │                │                    │
          └────────────────┼────────────────────┘
                           │
              ┌────────────▼────────────┐
              │   Claim/Deposit Bridge  │
              │   (SolanaTokenService)  │
              └────────────┬────────────┘
                           │
              ┌────────────▼────────────┐
              │      Solana Network     │
              │  ┌─────────────────────┐│
              │  │ SPL Token (AMOS)    ││
              │  │ Fixed 100M Supply   ││
              │  └─────────────────────┘│
              │  ┌─────────────────────┐│
              │  │ Treasury Wallet     ││
              │  │ (Multisig)          ││
              │  └─────────────────────┘│
              └─────────────────────────┘
                           │
              ┌────────────▼────────────┐
              │      Jupiter DEX        │
              │  (Trading / Swaps)      │
              └─────────────────────────┘
```

### 7.2 Internal vs On-Chain Tokens

| Aspect | Internal (Platform) | On-Chain (Solana) |
|--------|---------------------|-------------------|
| Decay | Yes (daily) | No (frozen) |
| Revenue Share | Yes | No (must deposit) |
| Governance | Yes | No (must deposit) |
| Trading | No | Yes |
| Gas Fees | None | ~$0.0003 |

### 7.3 Claim Flow

1. User requests claim via API
2. Platform validates balance
3. Background job sends SPL transfer
4. Internal balance deducted
5. User receives tokens in wallet

### 7.4 Deposit Flow

1. User sends tokens to treasury
2. User submits tx signature
3. Platform verifies on-chain
4. Internal stake created
5. User regains revenue/governance rights

---

## 8. Governance

### 8.1 Voting Power

Voting power proportional to current stake (post-decay):

```
Voting Power = Current Stake / Total Active Stakes
```

### 8.2 Governance Scope (Expanded)

Token holders vote on multiple categories with different requirements:

| Category | Description | Min Stake | Quorum | Threshold |
|----------|-------------|-----------|--------|-----------|
| **R&D Allocation** | 20% revenue budget | 1,000 | 30% | 50% (majority) |
| **Treasury Usage** | Fund usage proposals | 5,000 | 40% | 50% (majority) |
| **Feature Priority** | Feature prioritization | 500 | 20% | 50% (majority) |
| **Partnership** | Strategic partnerships | 2,500 | 35% | 50% (majority) |
| **Parameter Change** | Decay/halving adjustments | 10,000 | 50% | 66.7% (supermajority) |
| **Constitutional** | Core mechanic changes | 25,000 | 60% | 66.7% (supermajority) |

### 8.3 Proposal Process

1. Stake minimum AMOS to submit proposal (varies by type)
2. Discussion period (5-21 days depending on type)
3. Voting period (5-21 days depending on type)
4. Quorum must be met
5. Threshold must be passed
6. Failed proposals burn 10% of staked amount (anti-spam)

### 8.4 Supermajority Requirements

**Parameter** and **Constitutional** changes require:

- 2/3 (66.7%) approval to pass
- Higher quorum (50-60%)
- Longer discussion/voting periods
- Higher stake to propose

This protects core mechanics from minority capture while allowing evolution.

---

## 9. Security Considerations

### 9.1 Smart Contract Security

- SPL Token standard (battle-tested)
- No custom contract logic (reduces attack surface)
- Treasury protected by multisig (2-of-3)
- Mint authority permanently disabled

### 9.2 Platform Security

- Internal ledger is source of truth
- Decay runs in isolated background job
- Claim/deposit requires authenticated user
- Rate limiting on all endpoints

### 9.3 Economic Security

- Sybil resistant (KYC for large claims)
- Whale resistant (decay mechanism)
- Rug-proof (no admin keys on token)
- Governance capture resistant (supermajority for critical changes)

---

## 10. Technical Implementation

### 10.1 Key Models

```ruby
# TokenStake - Ownership record
class TokenStake
  belongs_to :user
  
  # Amounts
  :initial_amount    # Original stake
  :current_amount    # After decay
  
  # Graduated floor (grows with tenure)
  def current_floor_percentage
    # 5% → 10% → 15% → 25% based on years held
  end
  
  # Decay
  :decay_rate        # Annual rate
  :last_decay_at     # Last decay application
  
  # Vaulting
  :staking_tier      # bronze/silver/gold/permanent
  :locked_until      # Lock expiration
end

# GovernanceProposal - Voting proposals
class GovernanceProposal
  belongs_to :proposer
  has_many :governance_votes
  
  :proposal_type  # r_and_d, treasury, feature, partnership, parameter, constitutional
  :status         # draft, discussion, voting, passed, failed, cancelled, executed
  
  def requires_supermajority?
    [:parameter, :constitutional].include?(proposal_type.to_sym)
  end
end

# Contribution - Work record
class Contribution
  belongs_to :user
  
  :contribution_type
  :complexity
  :points          # Base points earned
  :token_value     # Tokens awarded from pool
  :status          # pending/approved/rejected
end
```

### 10.2 Key Services

```ruby
# Token decay (runs daily)
TokenDecayJob.perform_later

# Pool-based reward calculation
ContributionRewardCalculator.calculate(
  contribution_type: :feature,
  complexity: 3
)

# Solana operations
SolanaTokenService.send_tokens(to:, amount:)
SolanaTokenService.verify_deposit(tx:)

# DEX integration
JupiterSwapService.quote_amos_to_usdc(1000)
```

### 10.3 API Endpoints

```
# Token Economy
GET  /api/v1/token_economy/stats
GET  /api/v1/token_economy/distribution
GET  /api/v1/token_economy/leaderboard

# Wallet
POST /api/v1/wallet/connect
GET  /api/v1/wallet/balance
POST /api/v1/wallet/claim
POST /api/v1/wallet/deposit

# Governance
GET  /api/v1/governance/proposals
POST /api/v1/governance/proposals
POST /api/v1/governance/proposals/:id/vote
GET  /api/v1/governance/proposals/:id

# Swaps
GET  /api/v1/swap/quote
GET  /api/v1/swap/price
POST /api/v1/swap/prepare
```

---

## Appendix A: Glossary

| Term | Definition |
|------|------------|
| Decay | Gradual reduction of stake over time |
| Graduated Floor | Minimum stake % that grows with tenure (5%→25%) |
| Tenure | Time since stake was earned |
| Halving | Reduction of daily emission pool over time |
| Claim | Withdraw internal tokens to Solana wallet |
| Deposit | Return on-chain tokens to platform |
| Staking Vault | Time-lock for reduced decay |
| Supermajority | 2/3 (66.7%) approval required |
| Quorum | Minimum participation required for valid vote |

---

## Appendix B: Contract Addresses

| Network | Type | Address |
|---------|------|---------|
| Mainnet | Token Mint | TBD |
| Mainnet | Treasury | TBD |
| Devnet | Token Mint | TBD |
| Devnet | Treasury | TBD |

---

## Appendix C: Changelog

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | Jan 2026 | Pool-based rewards, graduated floor, success multipliers, expanded governance |
| 1.0 | Jan 2026 | Initial release |

---

*This document is for informational purposes only and does not constitute financial advice or a securities offering.*
