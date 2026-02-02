use anchor_lang::prelude::*;
use crate::state::*;
use crate::constants::{seeds, BPS_DENOMINATOR};

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct CalculatePriority<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,
}

/// Calculate the priority score for a proposal
/// 
/// Priority Formula:
/// priority = (mrr_weight * customer_vote_score) + (community_weight * community_votes) + recency_bonus
/// 
/// Where:
/// - customer_vote_score = sum of (MRR * vote_weight) for each customer request
/// - community_votes = total AMOS tokens voted
/// - recency_bonus = base_score * 2^(-days_since_submission / half_life)
pub fn calculate_priority(
    ctx: Context<CalculatePriority>,
    _proposal_id: u64,
) -> Result<u64> {
    let proposal = &ctx.accounts.proposal;
    let params = &ctx.accounts.governance_config.params;
    let clock = Clock::get()?;

    // Calculate MRR-weighted component
    let mrr_component = proposal.customer_vote_score
        .checked_mul(params.mrr_weight_bps as u64)
        .unwrap_or(0)
        .checked_div(BPS_DENOMINATOR)
        .unwrap_or(0);

    // Calculate community vote component
    let community_component = proposal.community_votes
        .checked_mul(params.community_weight_bps as u64)
        .unwrap_or(0)
        .checked_div(BPS_DENOMINATOR)
        .unwrap_or(0);

    // Calculate recency bonus
    // Uses exponential decay: bonus = base * 2^(-days / half_life)
    let days_since_submission = ((clock.unix_timestamp - proposal.submitted_at) / 86400) as u64;
    let half_life = params.recency_half_life_days as u64;
    
    // Approximate 2^(-x) using integer math: 2^(-n) ≈ 1 / 2^n
    // For simplicity, we decay by half for each half_life period
    let decay_periods = days_since_submission / half_life;
    let base_recency_bonus = 1000u64; // Base bonus of 1000 points
    
    let recency_bonus = if decay_periods >= 10 {
        0 // Cap at 10 half-lives (~0.1% remaining)
    } else {
        base_recency_bonus >> decay_periods // Bit shift = divide by 2^n
    };

    // Total priority
    let priority = mrr_component
        .checked_add(community_component)
        .unwrap_or(u64::MAX)
        .checked_add(recency_bonus)
        .unwrap_or(u64::MAX);

    msg!("Priority calculated: mrr={}, community={}, recency={}, total={}",
        mrr_component, community_component, recency_bonus, priority);

    Ok(priority)
}

/// Calculate priority scores for multiple proposals (off-chain helper)
/// This is meant to be called by the Rails app to rank proposals
pub fn calculate_priority_batch(
    proposals: &[FeatureProposal],
    params: &StoredGovernanceParams,
    current_timestamp: i64,
) -> Vec<(u64, u64)> {
    proposals.iter().map(|proposal| {
        let mrr_component = proposal.customer_vote_score
            .checked_mul(params.mrr_weight_bps as u64)
            .unwrap_or(0)
            .checked_div(BPS_DENOMINATOR)
            .unwrap_or(0);

        let community_component = proposal.community_votes
            .checked_mul(params.community_weight_bps as u64)
            .unwrap_or(0)
            .checked_div(BPS_DENOMINATOR)
            .unwrap_or(0);

        let days_since_submission = ((current_timestamp - proposal.submitted_at) / 86400) as u64;
        let half_life = params.recency_half_life_days as u64;
        let decay_periods = days_since_submission / half_life;
        let base_recency_bonus = 1000u64;
        
        let recency_bonus = if decay_periods >= 10 {
            0
        } else {
            base_recency_bonus >> decay_periods
        };

        let priority = mrr_component
            .checked_add(community_component)
            .unwrap_or(u64::MAX)
            .checked_add(recency_bonus)
            .unwrap_or(u64::MAX);

        (proposal.id, priority)
    }).collect()
}
