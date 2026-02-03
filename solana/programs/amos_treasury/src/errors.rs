use anchor_lang::prelude::*;

/// Treasury program error codes
#[error_code]
pub enum TreasuryError {
    /// Stake amount below minimum threshold
    #[msg("Stake amount is below the minimum required (100 AMOS)")]
    InsufficientStake,

    /// Stake not held long enough for revenue eligibility
    #[msg("Stake must be held for at least 30 days before claiming revenue")]
    StakeTooRecent,

    /// No revenue available to claim
    #[msg("No revenue available to claim at this time")]
    NoRevenueToClaim,

    /// Invalid payment amount (zero or overflow)
    #[msg("Invalid payment amount")]
    InvalidAmount,

    /// Arithmetic overflow in calculation
    #[msg("Arithmetic overflow in calculation")]
    ArithmeticOverflow,

    /// Treasury already initialized
    #[msg("Treasury has already been initialized")]
    AlreadyInitialized,

    /// Not authorized to perform this action
    #[msg("Not authorized to perform this action")]
    Unauthorized,

    /// Invalid multisig address
    #[msg("Invalid multisig address")]
    InvalidMultisig,

    /// Stake record not found
    #[msg("No stake record found for this wallet")]
    StakeNotFound,

    /// Payment reference too long
    #[msg("Payment reference must be 64 characters or less")]
    PaymentReferenceTooLong,

    /// Distribution history limit exceeded
    #[msg("Cannot store more than 1000 distribution records")]
    DistributionLimitExceeded,

    /// Reserve withdrawal requires DAO vote
    #[msg("Reserve funds can only be withdrawn via DAO governance vote")]
    ReserveWithdrawalRequiresVote,

    /// Holder pool insufficient balance
    #[msg("Holder pool has insufficient balance for this claim")]
    InsufficientPoolBalance,

    /// Invalid token mint
    #[msg("Invalid token mint - expected USDC or AMOS")]
    InvalidTokenMint,
}
