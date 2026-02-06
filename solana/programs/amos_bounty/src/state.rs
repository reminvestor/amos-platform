use anchor_lang::prelude::*;

/// ═══════════════════════════════════════════════════════════════════════════
/// BOUNTY PROGRAM CONFIGURATION
/// ═══════════════════════════════════════════════════════════════════════════

/// Global bounty program configuration
/// PDA: ["bounty_config"]
#[account]
#[derive(Default)]
pub struct BountyConfig {
    /// Platform oracle authority (submits bounty proofs)
    pub oracle_authority: Pubkey,
    
    /// AMOS token mint
    pub amos_mint: Pubkey,
    
    /// Treasury token account (source of emissions)
    pub treasury_token_account: Pubkey,
    
    /// Program start timestamp (for halving calculation)
    pub program_start_at: i64,
    
    /// Current halving epoch (0 = first year, 1 = second, etc.)
    pub current_halving_epoch: u8,
    
    /// Current daily emission rate (decreases with halving)
    pub current_daily_emission: u64,
    
    /// Total tokens ever distributed
    pub total_tokens_distributed: u64,
    
    /// Total bounty proofs submitted
    pub total_proofs_submitted: u64,
    
    /// Total bounty proofs approved
    pub total_proofs_approved: u64,
    
    /// Total tokens remaining in treasury pool
    pub treasury_remaining: u64,
    
    /// Current decay rate (basis points, set by oracle based on platform health)
    pub current_decay_rate_bps: u64,
    
    /// Last decay rate update timestamp
    pub decay_rate_updated_at: i64,
    
    /// Total tokens decayed (burned + recycled)
    pub total_decayed: u64,
    
    /// Total tokens burned from decay
    pub total_decay_burned: u64,
    
    /// Bump seed for PDA
    pub bump: u8,
    
    /// Reserved for future use
    pub _reserved: [u8; 32],
}

impl BountyConfig {
    pub const SIZE: usize = 8 + // discriminator
        32 + // oracle_authority
        32 + // amos_mint
        32 + // treasury_token_account
        8 +  // program_start_at
        1 +  // current_halving_epoch
        8 +  // current_daily_emission
        8 +  // total_tokens_distributed
        8 +  // total_proofs_submitted
        8 +  // total_proofs_approved
        8 +  // treasury_remaining
        8 +  // current_decay_rate_bps
        8 +  // decay_rate_updated_at
        8 +  // total_decayed
        8 +  // total_decay_burned
        1 +  // bump
        32;  // reserved
}

/// ═══════════════════════════════════════════════════════════════════════════
/// DAILY EMISSION POOL
/// ═══════════════════════════════════════════════════════════════════════════

/// Daily emission pool — tracks today's available tokens and total points
/// PDA: ["daily_pool", day_index]
#[account]
#[derive(Default)]
pub struct DailyPool {
    /// Day index (days since program start)
    pub day_index: u64,
    
    /// Total emission for this day
    pub total_emission: u64,
    
    /// Tokens already distributed today
    pub tokens_distributed: u64,
    
    /// Total points earned today (denominator for share calculation)
    pub total_points: u64,
    
    /// Number of bounty proofs submitted today
    pub proof_count: u64,
    
    /// Whether this day's pool is finalized (no more submissions)
    pub finalized: bool,
    
    /// Bump seed
    pub bump: u8,
}

impl DailyPool {
    pub const SIZE: usize = 8 + // discriminator
        8 +  // day_index
        8 +  // total_emission
        8 +  // tokens_distributed
        8 +  // total_points
        8 +  // proof_count
        1 +  // finalized
        1;   // bump
}

/// ═══════════════════════════════════════════════════════════════════════════
/// BOUNTY PROOF (submitted by platform oracle)
/// ═══════════════════════════════════════════════════════════════════════════

/// A proof of completed bounty work, submitted by the platform
/// PDA: ["bounty_proof", proof_reference]
#[account]
#[derive(Default)]
pub struct BountyProof {
    /// Platform bounty ID (for cross-reference)
    pub bounty_id: u64,
    
    /// Operator wallet (who receives the tokens)
    pub operator: Pubkey,
    
    /// Points earned for this bounty
    pub points: u64,
    
    /// Quality score (0-100, from AI + human review)
    pub quality_score: u8,
    
    /// Bounty type (0=bug, 1=feature, 2=docs, 3=content, 4=marketing,
    /// 5=support, 6=translation, 7=design, 8=testing, 9=infrastructure)
    pub bounty_type: u8,
    
    /// Whether this was completed by an external agent (EAP)
    pub is_external_agent: bool,
    
    /// External agent ID (if applicable)
    pub agent_id: u64,
    
    /// Agent trust level at time of completion
    pub agent_trust_level: u8,
    
    /// Day index when submitted (for daily pool allocation)
    pub day_index: u64,
    
    /// Tokens awarded (calculated from daily pool share)
    pub tokens_awarded: u64,
    
    /// Reviewer wallet (who reviewed the work)
    pub reviewer: Pubkey,
    
    /// Reviewer reward tokens
    pub reviewer_reward: u64,
    
    /// Hash of the work evidence (PR URL, commit SHA, etc.)
    pub evidence_hash: [u8; 32],
    
    /// Timestamp of proof submission
    pub submitted_at: i64,
    
    /// Proof reference string (unique identifier from platform)
    pub proof_reference: String,
    
    /// Bump seed
    pub bump: u8,
}

impl BountyProof {
    pub const SIZE: usize = 8 + // discriminator
        8 +  // bounty_id
        32 + // operator
        8 +  // points
        1 +  // quality_score
        1 +  // bounty_type
        1 +  // is_external_agent
        8 +  // agent_id
        1 +  // agent_trust_level
        8 +  // day_index
        8 +  // tokens_awarded
        32 + // reviewer
        8 +  // reviewer_reward
        32 + // evidence_hash
        8 +  // submitted_at
        4 + 64 + // proof_reference (String max 64)
        1;   // bump
}

/// ═══════════════════════════════════════════════════════════════════════════
/// OPERATOR STATS (token earnings tracker)
/// ═══════════════════════════════════════════════════════════════════════════

/// Per-operator statistics and token balance
/// PDA: ["operator_stats", operator_pubkey]
#[account]
#[derive(Default)]
pub struct OperatorStats {
    /// Operator wallet
    pub operator: Pubkey,
    
    /// Total bounties completed
    pub total_bounties: u64,
    
    /// Total points earned (lifetime)
    pub total_points: u64,
    
    /// Total AMOS tokens earned (lifetime)
    pub total_tokens_earned: u64,
    
    /// Current token balance (after decay)
    pub current_balance: u64,
    
    /// Original balance (before any decay)
    pub original_balance: u64,
    
    /// Tokens lost to decay
    pub total_decayed: u64,
    
    /// Last activity timestamp (resets decay grace period)
    pub last_active_at: i64,
    
    /// Today's bounty count (for daily limit enforcement)
    pub today_bounty_count: u64,
    
    /// Today's date index (to reset daily count)
    pub today_date_index: u64,
    
    /// Bump seed
    pub bump: u8,
}

impl OperatorStats {
    pub const SIZE: usize = 8 + // discriminator
        32 + // operator
        8 +  // total_bounties
        8 +  // total_points
        8 +  // total_tokens_earned
        8 +  // current_balance
        8 +  // original_balance
        8 +  // total_decayed
        8 +  // last_active_at
        8 +  // today_bounty_count
        8 +  // today_date_index
        1;   // bump
}

/// ═══════════════════════════════════════════════════════════════════════════
/// AGENT TRUST RECORD (on-chain trust level)
/// ═══════════════════════════════════════════════════════════════════════════

/// On-chain record of an external agent's trust level
/// PDA: ["agent_trust", agent_id]
#[account]
#[derive(Default)]
pub struct AgentTrustRecord {
    /// Platform agent ID
    pub agent_id: u64,
    
    /// Operator wallet
    pub operator: Pubkey,
    
    /// Current trust level (1-5)
    pub trust_level: u8,
    
    /// Total bounties completed (verified on-chain)
    pub total_completions: u64,
    
    /// Total bounties rejected
    pub total_rejections: u64,
    
    /// Reputation score (basis points, 0-10000)
    pub reputation_bps: u64,
    
    /// Total tokens earned by this agent
    pub total_tokens_earned: u64,
    
    /// Timestamp of last trust level change
    pub last_trust_change_at: i64,
    
    /// Timestamp of registration
    pub registered_at: i64,
    
    /// Bump seed
    pub bump: u8,
}

impl AgentTrustRecord {
    pub const SIZE: usize = 8 + // discriminator
        8 +  // agent_id
        32 + // operator
        1 +  // trust_level
        8 +  // total_completions
        8 +  // total_rejections
        8 +  // reputation_bps
        8 +  // total_tokens_earned
        8 +  // last_trust_change_at
        8 +  // registered_at
        1;   // bump
}
