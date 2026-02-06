use anchor_lang::prelude::*;

/// Bounty program error codes
#[error_code]
pub enum BountyError {
    /// Bounty points exceed maximum allowed
    #[msg("Bounty points exceed maximum allowed (2000)")]
    PointsExceedMaximum,

    /// Quality score below minimum threshold
    #[msg("Quality score below minimum threshold (30)")]
    QualityTooLow,

    /// Operator has exceeded daily bounty limit
    #[msg("Operator has exceeded daily bounty submission limit")]
    DailyLimitExceeded,

    /// Agent trust level insufficient for this bounty
    #[msg("Agent trust level insufficient for this bounty point value")]
    TrustLevelInsufficient,

    /// Agent does not meet trust upgrade requirements
    #[msg("Agent does not meet requirements for trust level upgrade")]
    TrustUpgradeNotEligible,

    /// Trust level already at maximum
    #[msg("Agent is already at maximum trust level")]
    AlreadyMaxTrust,

    /// Daily emission pool is depleted
    #[msg("Daily emission pool has been fully distributed")]
    EmissionPoolDepleted,

    /// Treasury pool exhausted
    #[msg("Treasury token pool is exhausted — no more tokens to emit")]
    TreasuryExhausted,

    /// Arithmetic overflow in calculation
    #[msg("Arithmetic overflow in calculation")]
    ArithmeticOverflow,

    /// Not authorized to perform this action
    #[msg("Not authorized to perform this action")]
    Unauthorized,

    /// Invalid oracle authority
    #[msg("Only the platform oracle can submit bounty proofs")]
    InvalidOracle,

    /// Bounty proof already submitted for this reference
    #[msg("A bounty proof with this reference already exists")]
    DuplicateProof,

    /// Invalid bounty type
    #[msg("Invalid bounty type — must be 0-9")]
    InvalidBountyType,

    /// Decay rate out of allowed range
    #[msg("Decay rate must be between 2% and 25% annually")]
    DecayRateOutOfRange,

    /// Stake is within grace period (no decay)
    #[msg("Stake is within the 90-day grace period — no decay applies")]
    WithinGracePeriod,

    /// Stake already at decay floor
    #[msg("Stake is already at the decay floor (10% of original)")]
    AtDecayFloor,

    /// Program already initialized
    #[msg("Bounty program has already been initialized")]
    AlreadyInitialized,

    /// Invalid halving epoch
    #[msg("Invalid halving epoch")]
    InvalidHalvingEpoch,

    /// Reviewer cannot review their own work
    #[msg("Reviewer cannot review their own bounty submission")]
    SelfReviewNotAllowed,
}
