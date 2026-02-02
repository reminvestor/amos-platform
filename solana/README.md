# Amos Governance - Solana Program

On-chain governance program for the Amos Labs platform. This program manages the trustless, auditable governance layer that controls:

- Feature proposal lifecycle and voting
- Research proposal funding and graduation  
- Priority scoring algorithm (MRR-weighted)
- Quality gate thresholds and results
- Staged reward calculations and claims
- Parameter governance for algorithm updates

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Rails Application                             │
│  (app.amos.com / build.amos.com / gov.amos.com)                     │
├─────────────────────────────────────────────────────────────────────┤
│  GovernanceChainService  │  OracleService  │  ChainSyncService      │
│  - Submit proposals      │  - Report gates │  - Sync state          │
│  - Cast votes            │  - Benchmark    │  - Cache proposals     │
│  - Claim rewards         │  - A/B tests    │  - Update priorities   │
└─────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Solana Blockchain                                │
├─────────────────────────────────────────────────────────────────────┤
│  amos_governance Program                                            │
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ GovernanceConfig (PDA)                                          ││
│  │ - Authority / Oracle Authority                                   ││
│  │ - Algorithm Parameters (weights, thresholds)                    ││
│  │ - Treasury Account                                              ││
│  └─────────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ FeatureProposal (PDA per proposal)                              ││
│  │ - Status / Votes / Gates / Rewards                              ││
│  └─────────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ ResearchProposal (PDA per research)                             ││
│  │ - Milestones / Stipend / Graduation                             ││
│  └─────────────────────────────────────────────────────────────────┘│
│  ┌─────────────────────────────────────────────────────────────────┐│
│  │ VoteRecord (PDA per voter per proposal)                         ││
│  │ - Escrowed tokens / Withdrawal                                  ││
│  └─────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

## Why On-Chain?

1. **Trustless**: The algorithm that determines priority and rewards cannot be secretly modified
2. **Auditable**: Anyone can verify how proposals are ranked and rewards distributed
3. **Immutable**: Parameter changes require governance votes and time locks
4. **Decentralized**: No single party controls the algorithm

## Key Concepts

### Priority Algorithm

```
priority = (mrr_weight × customer_vote_score) + (community_weight × community_votes) + recency_bonus
```

- **MRR Weight** (60% default): Customer requests weighted by their MRR contribution
- **Community Weight** (40% default): AMOS tokens staked as votes
- **Recency Bonus**: Exponential decay with 30-day half-life

### Quality Gates

1. **Benchmark Gate**: Automated tests must pass with >70% score
2. **A/B Test Gate**: Feature must show >5% improvement
3. **Feedback Gate**: >70% positive customer feedback
4. **Steward Gate**: 3+ steward council approvals

### Staged Rewards

- **40%** on benchmark completion
- **30%** on A/B test success
- **30%** on stable merge to main

### Research Track

- **20%** upfront stipend on approval
- **80%** success bonus on graduation to feature
- Milestones tracked on-chain

## Development

### Prerequisites

- Rust 1.70+
- Solana CLI 1.17+
- Anchor 0.29+
- Node.js 18+

### Build

```bash
cd solana
anchor build
```

### Test

```bash
anchor test
```

### Deploy

```bash
# Devnet
anchor deploy --provider.cluster devnet

# Mainnet (requires multi-sig)
anchor deploy --provider.cluster mainnet
```

## Program Instructions

### Governance

- `initialize_governance` - One-time setup with initial parameters
- `update_governance_params` - Update algorithm parameters (time-locked)

### Proposals

- `submit_feature_proposal` - Create a new feature proposal
- `vote_for_feature` - Stake AMOS tokens as vote
- `withdraw_vote` - Withdraw vote and reclaim tokens
- `update_proposal_status` - Oracle updates proposal status

### Quality Gates

- `report_benchmark_result` - Oracle reports benchmark pass/fail
- `report_ab_test_result` - Oracle reports A/B test results
- `report_feedback_result` - Oracle reports customer feedback
- `report_steward_approval` - Oracle reports steward council vote

### Rewards

- `claim_bounty_reward` - Builder claims reward for completed gate
- `finalize_rewards` - Mark proposal as merged, enable final reward

### Research

- `submit_research_proposal` - Create research proposal
- `approve_research` - Steward council approves, pays stipend
- `report_research_milestone` - Track milestone completion
- `graduate_research` - Convert research to feature proposal

### View Functions

- `calculate_priority` - Calculate priority score for a proposal

## Security Considerations

### Oracle Security

The oracle authority can only:
- Report gate results (not change them retroactively)
- Update proposal status through valid transitions
- Cannot: modify votes, change parameters, withdraw funds

Oracle authority should be:
- Multi-sig controlled
- Rate-limited
- Monitored for anomalous behavior

### Time Locks

Parameter changes have a 3-day time lock to allow community review.

### Vote Locking

Votes are locked until the proposal completes A/B testing to prevent vote manipulation.

## Integration with Rails

See `app/services/governance_chain_service.rb` for the Rails integration layer.

```ruby
# Submit a proposal
GovernanceChainService.submit_proposal(
  title: "Add dark mode",
  description: "...",
  bounty: 1000_00000000, # 1000 AMOS
  customer_request_ids: [123, 456]
)

# Report benchmark result
GovernanceChainService.oracle.report_benchmark(
  proposal_id: 42,
  passed: true,
  score: 8500,
  evidence_hash: "Qm..."
)

# Claim reward
GovernanceChainService.claim_reward(
  proposal_id: 42,
  gate_type: :benchmark,
  builder_wallet: "..."
)
```

## License

Apache-2.0
