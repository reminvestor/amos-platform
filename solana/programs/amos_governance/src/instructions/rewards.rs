use anchor_lang::prelude::*;
use crate::state::*;
use crate::errors::GovernanceError;
use crate::constants::{seeds, BPS_DENOMINATOR};
use crate::{ProposalStatus, GateType};

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct ClaimBountyReward<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,

    /// Treasury token account
    #[account(
        mut,
        seeds = [seeds::TREASURY],
        bump,
        token::mint = governance_config.amos_mint,
    )]
    pub treasury: Account<'info, anchor_spl::token::TokenAccount>,

    /// Builder's token account to receive reward
    #[account(
        mut,
        token::mint = governance_config.amos_mint,
        token::authority = builder,
    )]
    pub builder_token_account: Account<'info, anchor_spl::token::TokenAccount>,

    /// Builder claiming the reward
    #[account(mut)]
    pub builder: Signer<'info>,

    pub token_program: Program<'info, anchor_spl::token::Token>,
}

pub fn claim_bounty_reward(
    ctx: Context<ClaimBountyReward>,
    _proposal_id: u64,
    gate_type: GateType,
) -> Result<()> {
    let proposal = &mut ctx.accounts.proposal;
    let governance = &ctx.accounts.governance_config;

    // Verify builder is assigned to this proposal
    require!(
        proposal.builder == Some(ctx.accounts.builder.key()),
        GovernanceError::Unauthorized
    );

    // Get the gate result and calculate reward
    let (gate, reward_bps) = match gate_type {
        GateType::Benchmark => {
            (&mut proposal.gates.benchmark, governance.params.bounty_completion_bps)
        }
        GateType::AbTest => {
            (&mut proposal.gates.ab_test, governance.params.bounty_ab_success_bps)
        }
        GateType::CustomerFeedback => {
            // Feedback is part of the completion reward
            return Err(GovernanceError::InvalidProposalStatus.into());
        }
        GateType::StewardApproval => {
            // Steward approval unlocks the final merge reward
            return Err(GovernanceError::InvalidProposalStatus.into());
        }
        GateType::FinalMerge => {
            (&mut proposal.gates.final_merge, governance.params.bounty_stable_merge_bps)
        }
    };

    require!(gate.evaluated, GovernanceError::GateNotEvaluated);
    require!(gate.passed, GovernanceError::GateNotPassed);
    require!(!gate.reward_claimed, GovernanceError::RewardAlreadyClaimed);

    // Calculate reward amount
    let reward_amount = proposal.bounty_amount
        .checked_mul(reward_bps as u64)
        .ok_or(GovernanceError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    // Transfer reward from treasury
    let seeds = &[seeds::GOVERNANCE_CONFIG, &[governance.bump]];
    let signer_seeds = &[&seeds[..]];

    anchor_spl::token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            anchor_spl::token::Transfer {
                from: ctx.accounts.treasury.to_account_info(),
                to: ctx.accounts.builder_token_account.to_account_info(),
                authority: ctx.accounts.governance_config.to_account_info(),
            },
            signer_seeds,
        ),
        reward_amount,
    )?;

    // Mark as claimed
    gate.reward_claimed = true;
    proposal.bounty_claimed = proposal.bounty_claimed
        .checked_add(reward_amount)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    msg!("Reward of {} tokens claimed for {:?} gate", reward_amount, gate_type);

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct FinalizeRewards<'info> {
    #[account(
        mut,
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

pub fn finalize_rewards(
    ctx: Context<FinalizeRewards>,
    _proposal_id: u64,
) -> Result<()> {
    let proposal = &mut ctx.accounts.proposal;
    let governance = &mut ctx.accounts.governance_config;
    let clock = Clock::get()?;

    // Ensure proposal is approved
    require!(
        proposal.status == ProposalStatus::Approved,
        GovernanceError::InvalidProposalStatus
    );

    // Ensure all gates passed
    require!(
        proposal.gates.benchmark.passed &&
        proposal.gates.ab_test.passed &&
        proposal.gates.feedback.passed &&
        proposal.gates.steward.passed,
        GovernanceError::GatesNotComplete
    );

    // Mark final merge gate as complete
    proposal.gates.final_merge = GateResult {
        evaluated: true,
        passed: true,
        score: 0,
        evidence_hash: [0u8; 32],
        evaluated_at: clock.unix_timestamp,
        reward_claimed: false,
    };

    // Update proposal status
    proposal.status = ProposalStatus::Merged;
    proposal.completed_at = Some(clock.unix_timestamp);

    // Track total rewards
    governance.total_rewards_distributed = governance.total_rewards_distributed
        .checked_add(proposal.bounty_amount)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    msg!("Proposal finalized and merged");

    Ok(())
}
