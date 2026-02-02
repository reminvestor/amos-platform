use anchor_lang::prelude::*;
use crate::{ProposalStatus, GateType, GovernanceConfigParams};

/// Global governance configuration account
/// PDA: ["governance_config"]
#[account]
#[derive(Default)]
pub struct GovernanceConfig {
    /// Authority that can update governance params (multi-sig)
    pub authority: Pubkey,
    /// Oracle authority that can report gate results
    pub oracle_authority: Pubkey,
    /// AMOS token mint
    pub amos_mint: Pubkey,
    /// Treasury account for rewards
    pub treasury: Pubkey,
    /// Configuration parameters
    pub params: StoredGovernanceParams,
    /// Total proposals submitted
    pub total_proposals: u64,
    /// Total research proposals submitted
    pub total_research_proposals: u64,
    /// Total rewards distributed
    pub total_rewards_distributed: u64,
    /// Bump seed for PDA
    pub bump: u8,
    /// Reserved for future use
    pub _reserved: [u8; 64],
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Default)]
pub struct StoredGovernanceParams {
    pub mrr_weight_bps: u16,
    pub community_weight_bps: u16,
    pub recency_half_life_days: u16,
    pub min_benchmark_score: u16,
    pub min_ab_improvement_bps: i16,
    pub min_feedback_ratio_bps: u16,
    pub steward_quorum: u8,
    pub bounty_completion_bps: u16,
    pub bounty_ab_success_bps: u16,
    pub bounty_stable_merge_bps: u16,
    pub research_stipend_bps: u16,
    pub research_success_multiplier_bps: u16,
}

impl From<GovernanceConfigParams> for StoredGovernanceParams {
    fn from(params: GovernanceConfigParams) -> Self {
        Self {
            mrr_weight_bps: params.mrr_weight_bps,
            community_weight_bps: params.community_weight_bps,
            recency_half_life_days: params.recency_half_life_days,
            min_benchmark_score: params.min_benchmark_score,
            min_ab_improvement_bps: params.min_ab_improvement_bps,
            min_feedback_ratio_bps: params.min_feedback_ratio_bps,
            steward_quorum: params.steward_quorum,
            bounty_completion_bps: params.bounty_completion_bps,
            bounty_ab_success_bps: params.bounty_ab_success_bps,
            bounty_stable_merge_bps: params.bounty_stable_merge_bps,
            research_stipend_bps: params.research_stipend_bps,
            research_success_multiplier_bps: params.research_success_multiplier_bps,
        }
    }
}

impl GovernanceConfig {
    pub const LEN: usize = 8 + // discriminator
        32 + // authority
        32 + // oracle_authority
        32 + // amos_mint
        32 + // treasury
        (2 * 12) + // params (12 fields, mostly u16)
        8 + // total_proposals
        8 + // total_research_proposals
        8 + // total_rewards_distributed
        1 + // bump
        64; // reserved
}

/// Feature proposal account
/// PDA: ["feature_proposal", proposal_id]
#[account]
pub struct FeatureProposal {
    /// Unique proposal ID
    pub id: u64,
    /// Proposer's wallet
    pub proposer: Pubkey,
    /// Builder assigned to implement (if any)
    pub builder: Option<Pubkey>,
    /// Title hash (actual content stored off-chain)
    pub title_hash: [u8; 32],
    /// Description hash (actual content stored off-chain)
    pub description_hash: [u8; 32],
    /// Current status
    pub status: ProposalStatus,
    /// Total bounty in AMOS tokens (lamports)
    pub bounty_amount: u64,
    /// Bounty already claimed
    pub bounty_claimed: u64,
    /// Total community votes (AMOS tokens)
    pub community_votes: u64,
    /// MRR-weighted customer vote score
    pub customer_vote_score: u64,
    /// Number of customer requests linked
    pub customer_request_count: u16,
    /// Timestamp when submitted
    pub submitted_at: i64,
    /// Timestamp when development started
    pub development_started_at: Option<i64>,
    /// Timestamp when completed
    pub completed_at: Option<i64>,
    /// Gate results
    pub gates: GateResults,
    /// Bump seed
    pub bump: u8,
    /// Reserved
    pub _reserved: [u8; 32],
}

impl FeatureProposal {
    pub const LEN: usize = 8 + // discriminator
        8 + // id
        32 + // proposer
        33 + // builder (Option<Pubkey>)
        32 + // title_hash
        32 + // description_hash
        1 + // status
        8 + // bounty_amount
        8 + // bounty_claimed
        8 + // community_votes
        8 + // customer_vote_score
        2 + // customer_request_count
        8 + // submitted_at
        9 + // development_started_at (Option<i64>)
        9 + // completed_at (Option<i64>)
        GateResults::LEN + // gates
        1 + // bump
        32; // reserved
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Default)]
pub struct GateResults {
    /// Benchmark gate
    pub benchmark: GateResult,
    /// A/B test gate
    pub ab_test: GateResult,
    /// Customer feedback gate
    pub feedback: GateResult,
    /// Steward approval gate
    pub steward: GateResult,
    /// Final merge confirmation
    pub final_merge: GateResult,
}

impl GateResults {
    pub const LEN: usize = GateResult::LEN * 5;
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Default)]
pub struct GateResult {
    /// Whether this gate has been evaluated
    pub evaluated: bool,
    /// Whether the gate passed
    pub passed: bool,
    /// Score/metric for this gate
    pub score: i32,
    /// Hash of evidence (IPFS CID, etc.)
    pub evidence_hash: [u8; 32],
    /// Timestamp of evaluation
    pub evaluated_at: i64,
    /// Reward claimed for this gate
    pub reward_claimed: bool,
}

impl GateResult {
    pub const LEN: usize = 1 + 1 + 4 + 32 + 8 + 1;
}

/// Vote record for a proposal
/// PDA: ["vote", proposal_id, voter]
#[account]
pub struct VoteRecord {
    /// Proposal this vote is for
    pub proposal_id: u64,
    /// Voter wallet
    pub voter: Pubkey,
    /// Amount of AMOS tokens staked as vote
    pub vote_amount: u64,
    /// Timestamp of vote
    pub voted_at: i64,
    /// Whether vote has been withdrawn
    pub withdrawn: bool,
    /// Bump seed
    pub bump: u8,
}

impl VoteRecord {
    pub const LEN: usize = 8 + // discriminator
        8 + // proposal_id
        32 + // voter
        8 + // vote_amount
        8 + // voted_at
        1 + // withdrawn
        1; // bump
}

/// Research proposal account
/// PDA: ["research_proposal", proposal_id]
#[account]
pub struct ResearchProposal {
    /// Unique research proposal ID
    pub id: u64,
    /// Researcher wallet
    pub researcher: Pubkey,
    /// Title hash
    pub title_hash: [u8; 32],
    /// Description hash
    pub description_hash: [u8; 32],
    /// Current status
    pub status: ResearchStatus,
    /// Requested stipend amount
    pub requested_stipend: u64,
    /// Approved stipend amount
    pub approved_stipend: u64,
    /// Stipend already paid
    pub stipend_paid: u64,
    /// Total milestones
    pub total_milestones: u8,
    /// Completed milestones
    pub completed_milestones: u8,
    /// Milestone evidence hashes
    pub milestone_hashes: [[u8; 32]; 10],
    /// Timestamp when submitted
    pub submitted_at: i64,
    /// Timestamp when approved
    pub approved_at: Option<i64>,
    /// Timestamp when completed
    pub completed_at: Option<i64>,
    /// Graduated to feature proposal ID (if any)
    pub graduated_to: Option<u64>,
    /// Bump seed
    pub bump: u8,
    /// Reserved
    pub _reserved: [u8; 32],
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Default)]
pub enum ResearchStatus {
    #[default]
    Draft,
    Submitted,
    Approved,
    InProgress,
    Completed,
    Graduated,
    Rejected,
    Cancelled,
}

impl ResearchProposal {
    pub const LEN: usize = 8 + // discriminator
        8 + // id
        32 + // researcher
        32 + // title_hash
        32 + // description_hash
        1 + // status
        8 + // requested_stipend
        8 + // approved_stipend
        8 + // stipend_paid
        1 + // total_milestones
        1 + // completed_milestones
        (32 * 10) + // milestone_hashes
        8 + // submitted_at
        9 + // approved_at
        9 + // completed_at
        9 + // graduated_to
        1 + // bump
        32; // reserved
}

/// Customer request reference (for priority calculation)
/// PDA: ["customer_request", request_id]
#[account]
pub struct CustomerRequest {
    /// Platform request ID (from Rails app)
    pub request_id: u64,
    /// Customer's MRR contribution (in cents)
    pub mrr_cents: u64,
    /// Linked proposal ID
    pub proposal_id: Option<u64>,
    /// Timestamp when linked
    pub linked_at: i64,
    /// Bump seed
    pub bump: u8,
}

impl CustomerRequest {
    pub const LEN: usize = 8 + // discriminator
        8 + // request_id
        8 + // mrr_cents
        9 + // proposal_id
        8 + // linked_at
        1; // bump
}
