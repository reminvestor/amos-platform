/// Maximum title length in bytes
pub const MAX_TITLE_LEN: usize = 64;

/// Maximum description length in bytes
pub const MAX_DESCRIPTION_LEN: usize = 500;

/// Maximum customer requests per proposal
pub const MAX_CUSTOMER_REQUESTS: usize = 100;

/// Maximum milestones per research proposal
pub const MAX_MILESTONES: u8 = 10;

/// Basis points denominator (100% = 10000)
pub const BPS_DENOMINATOR: u64 = 10000;

/// Default governance parameters
pub mod defaults {
    /// MRR weight: 60%
    pub const MRR_WEIGHT_BPS: u16 = 6000;
    
    /// Community weight: 40%
    pub const COMMUNITY_WEIGHT_BPS: u16 = 4000;
    
    /// Recency half-life: 30 days
    pub const RECENCY_HALF_LIFE_DAYS: u16 = 30;
    
    /// Minimum benchmark score: 70%
    pub const MIN_BENCHMARK_SCORE: u16 = 7000;
    
    /// Minimum A/B improvement: 5%
    pub const MIN_AB_IMPROVEMENT_BPS: i16 = 500;
    
    /// Minimum feedback approval: 70%
    pub const MIN_FEEDBACK_RATIO_BPS: u16 = 7000;
    
    /// Steward quorum: 3 approvals
    pub const STEWARD_QUORUM: u8 = 3;
    
    /// Bounty on completion: 40%
    pub const BOUNTY_COMPLETION_BPS: u16 = 4000;
    
    /// Bounty on A/B success: 30%
    pub const BOUNTY_AB_SUCCESS_BPS: u16 = 3000;
    
    /// Bounty on stable merge: 30%
    pub const BOUNTY_STABLE_MERGE_BPS: u16 = 3000;
    
    /// Research stipend: 20% upfront
    pub const RESEARCH_STIPEND_BPS: u16 = 2000;
    
    /// Research success multiplier: 400% (80% of remaining)
    pub const RESEARCH_SUCCESS_MULTIPLIER_BPS: u16 = 4000;
}

/// PDA seeds
pub mod seeds {
    pub const GOVERNANCE_CONFIG: &[u8] = b"governance_config";
    pub const FEATURE_PROPOSAL: &[u8] = b"feature_proposal";
    pub const RESEARCH_PROPOSAL: &[u8] = b"research_proposal";
    pub const VOTE_RECORD: &[u8] = b"vote";
    pub const CUSTOMER_REQUEST: &[u8] = b"customer_request";
    pub const TREASURY: &[u8] = b"treasury";
}

/// Time constants (in seconds)
pub mod time {
    /// Proposal expiration: 90 days
    pub const PROPOSAL_EXPIRATION_SECONDS: i64 = 90 * 24 * 60 * 60;
    
    /// Vote lock period: 7 days
    pub const VOTE_LOCK_SECONDS: i64 = 7 * 24 * 60 * 60;
    
    /// Parameter change time lock: 3 days
    pub const PARAM_CHANGE_TIME_LOCK_SECONDS: i64 = 3 * 24 * 60 * 60;
}
