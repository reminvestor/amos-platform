use anchor_lang::prelude::*;
use crate::state::*;
use crate::errors::GovernanceError;
use crate::constants::seeds;
use crate::ProposalStatus;

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct ReportBenchmarkResult<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = oracle_authority @ GovernanceError::UnauthorizedOracle,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,

    pub oracle_authority: Signer<'info>,
}

pub fn report_benchmark_result(
    ctx: Context<ReportBenchmarkResult>,
    _proposal_id: u64,
    passed: bool,
    score: u16,
    evidence_hash: [u8; 32],
) -> Result<()> {
    let proposal = &mut ctx.accounts.proposal;
    let clock = Clock::get()?;

    require!(
        proposal.status == ProposalStatus::InReview,
        GovernanceError::InvalidProposalStatus
    );
    require!(
        !proposal.gates.benchmark.evaluated,
        GovernanceError::GateAlreadyEvaluated
    );

    proposal.gates.benchmark = GateResult {
        evaluated: true,
        passed,
        score: score as i32,
        evidence_hash,
        evaluated_at: clock.unix_timestamp,
        reward_claimed: false,
    };

    // Auto-update status based on result
    if passed {
        proposal.status = ProposalStatus::InAbTest;
    } else {
        proposal.status = ProposalStatus::InReview; // Needs fixes
    }

    msg!("Benchmark result reported: passed={}, score={}", passed, score);

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct ReportAbTestResult<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = oracle_authority @ GovernanceError::UnauthorizedOracle,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,

    pub oracle_authority: Signer<'info>,
}

pub fn report_ab_test_result(
    ctx: Context<ReportAbTestResult>,
    _proposal_id: u64,
    passed: bool,
    improvement_bps: i16,
    sample_size: u32,
    confidence_bps: u16,
    evidence_hash: [u8; 32],
) -> Result<()> {
    let proposal = &mut ctx.accounts.proposal;
    let clock = Clock::get()?;

    require!(
        proposal.status == ProposalStatus::InAbTest,
        GovernanceError::InvalidProposalStatus
    );
    require!(
        !proposal.gates.ab_test.evaluated,
        GovernanceError::GateAlreadyEvaluated
    );

    // Store improvement as score (can be negative)
    proposal.gates.ab_test = GateResult {
        evaluated: true,
        passed,
        score: improvement_bps as i32,
        evidence_hash,
        evaluated_at: clock.unix_timestamp,
        reward_claimed: false,
    };

    if passed {
        proposal.status = ProposalStatus::AwaitingFeedback;
    }

    msg!(
        "A/B test result reported: passed={}, improvement={}bps, sample={}, confidence={}bps",
        passed, improvement_bps, sample_size, confidence_bps
    );

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct ReportFeedbackResult<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = oracle_authority @ GovernanceError::UnauthorizedOracle,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,

    pub oracle_authority: Signer<'info>,
}

pub fn report_feedback_result(
    ctx: Context<ReportFeedbackResult>,
    _proposal_id: u64,
    passed: bool,
    positive_count: u32,
    negative_count: u32,
    evidence_hash: [u8; 32],
) -> Result<()> {
    let proposal = &mut ctx.accounts.proposal;
    let clock = Clock::get()?;

    require!(
        proposal.status == ProposalStatus::AwaitingFeedback,
        GovernanceError::InvalidProposalStatus
    );
    require!(
        !proposal.gates.feedback.evaluated,
        GovernanceError::GateAlreadyEvaluated
    );

    // Calculate approval ratio as score (in basis points)
    let total = positive_count + negative_count;
    let ratio_bps = if total > 0 {
        ((positive_count as u64 * 10000) / total as u64) as i32
    } else {
        0
    };

    proposal.gates.feedback = GateResult {
        evaluated: true,
        passed,
        score: ratio_bps,
        evidence_hash,
        evaluated_at: clock.unix_timestamp,
        reward_claimed: false,
    };

    if passed {
        proposal.status = ProposalStatus::AwaitingStewardApproval;
    }

    msg!(
        "Feedback result reported: passed={}, positive={}, negative={}, ratio={}bps",
        passed, positive_count, negative_count, ratio_bps
    );

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct ReportStewardApproval<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = oracle_authority @ GovernanceError::UnauthorizedOracle,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,

    pub oracle_authority: Signer<'info>,
}

pub fn report_steward_approval(
    ctx: Context<ReportStewardApproval>,
    _proposal_id: u64,
    approved: bool,
    approvals: u8,
    rejections: u8,
) -> Result<()> {
    let proposal = &mut ctx.accounts.proposal;
    let clock = Clock::get()?;

    require!(
        proposal.status == ProposalStatus::AwaitingStewardApproval,
        GovernanceError::InvalidProposalStatus
    );
    require!(
        !proposal.gates.steward.evaluated,
        GovernanceError::GateAlreadyEvaluated
    );

    proposal.gates.steward = GateResult {
        evaluated: true,
        passed: approved,
        score: approvals as i32,
        evidence_hash: [0u8; 32], // No external evidence needed
        evaluated_at: clock.unix_timestamp,
        reward_claimed: false,
    };

    if approved {
        proposal.status = ProposalStatus::Approved;
    } else {
        proposal.status = ProposalStatus::Rejected;
    }

    msg!(
        "Steward approval reported: approved={}, votes={}-{}",
        approved, approvals, rejections
    );

    Ok(())
}
