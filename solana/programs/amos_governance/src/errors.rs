use anchor_lang::prelude::*;

#[error_code]
pub enum GovernanceError {
    #[msg("Unauthorized: caller is not the authority")]
    Unauthorized,

    #[msg("Unauthorized: caller is not the oracle authority")]
    UnauthorizedOracle,

    #[msg("Invalid proposal status for this operation")]
    InvalidProposalStatus,

    #[msg("Proposal not found")]
    ProposalNotFound,

    #[msg("Vote already exists for this proposal")]
    VoteAlreadyExists,

    #[msg("Vote not found")]
    VoteNotFound,

    #[msg("Vote already withdrawn")]
    VoteAlreadyWithdrawn,

    #[msg("Insufficient vote amount")]
    InsufficientVoteAmount,

    #[msg("Gate already evaluated")]
    GateAlreadyEvaluated,

    #[msg("Gate not yet evaluated")]
    GateNotEvaluated,

    #[msg("Gate did not pass")]
    GateNotPassed,

    #[msg("Reward already claimed for this gate")]
    RewardAlreadyClaimed,

    #[msg("All gates must pass before finalizing")]
    GatesNotComplete,

    #[msg("Research proposal not found")]
    ResearchNotFound,

    #[msg("Invalid research status for this operation")]
    InvalidResearchStatus,

    #[msg("Research not yet approved")]
    ResearchNotApproved,

    #[msg("Invalid milestone index")]
    InvalidMilestoneIndex,

    #[msg("Milestone already completed")]
    MilestoneAlreadyCompleted,

    #[msg("Research already graduated")]
    ResearchAlreadyGraduated,

    #[msg("Insufficient funds in treasury")]
    InsufficientTreasuryFunds,

    #[msg("Invalid governance parameters")]
    InvalidGovernanceParams,

    #[msg("Title too long (max 64 chars)")]
    TitleTooLong,

    #[msg("Description too long (max 500 chars)")]
    DescriptionTooLong,

    #[msg("Too many customer requests (max 100)")]
    TooManyCustomerRequests,

    #[msg("Too many milestones (max 10)")]
    TooManyMilestones,

    #[msg("Arithmetic overflow")]
    ArithmeticOverflow,

    #[msg("Time lock not expired")]
    TimeLockNotExpired,

    #[msg("Proposal expired")]
    ProposalExpired,
}
