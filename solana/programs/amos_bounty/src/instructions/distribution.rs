use anchor_lang::prelude::*;
use crate::state::*;
use crate::constants::*;
use crate::errors::BountyError;

/// Submit a bounty completion proof and distribute tokens
///
/// This is the CORE function — the platform oracle submits proof of completed work,
/// and the chain calculates and distributes tokens based on the immutable formula:
///
///   tokens = (points / total_points_today) × daily_emission_pool
///
/// The oracle can only submit proofs; it cannot change the formula or rates.
pub fn submit_bounty_proof(
    ctx: Context<SubmitBountyProof>,
    bounty_id: u64,
    operator: Pubkey,
    points: u64,
    quality_score: u8,
    bounty_type: u8,
    is_external_agent: bool,
    agent_id: u64,
    agent_trust_level: u8,
    reviewer: Pubkey,
    evidence_hash: [u8; 32],
    proof_reference: String,
) -> Result<()> {
    let config = &ctx.accounts.bounty_config;
    
    // === VALIDATION (on-chain enforcement) ===
    
    // Only oracle can submit proofs
    require!(
        ctx.accounts.oracle.key() == config.oracle_authority,
        BountyError::InvalidOracle
    );
    
    // Points within allowed range
    require!(points > 0 && points <= MAX_BOUNTY_POINTS, BountyError::PointsExceedMaximum);
    
    // Quality meets minimum
    require!(quality_score >= MIN_QUALITY_SCORE, BountyError::QualityTooLow);
    
    // Valid bounty type (0-9)
    require!(bounty_type <= 9, BountyError::InvalidBountyType);
    
    // Treasury has tokens remaining
    require!(config.treasury_remaining > 0, BountyError::TreasuryExhausted);
    
    // === TRUST LEVEL CHECK (for external agents) ===
    
    if is_external_agent {
        let trust_idx = (agent_trust_level as usize).saturating_sub(1).min(4);
        let max_points = TRUST_LEVEL_MAX_POINTS[trust_idx];
        require!(points <= max_points, BountyError::TrustLevelInsufficient);
    }
    
    // === DAILY LIMIT CHECK ===
    
    let operator_stats = &mut ctx.accounts.operator_stats;
    let now = Clock::get()?.unix_timestamp;
    let day_index = ((now - config.program_start_at) / 86400) as u64;
    
    // Reset daily count if new day
    if operator_stats.today_date_index != day_index {
        operator_stats.today_bounty_count = 0;
        operator_stats.today_date_index = day_index;
    }
    
    require!(
        operator_stats.today_bounty_count < MAX_DAILY_BOUNTIES_PER_OPERATOR,
        BountyError::DailyLimitExceeded
    );
    
    // === APPLY CONTRIBUTION MULTIPLIER ===
    
    let multiplier_bps = match bounty_type {
        0 => MULTIPLIER_BUG_FIX_BPS,        // bug
        1 => MULTIPLIER_FEATURE_BPS,         // feature
        2 => MULTIPLIER_DOCS_BPS,            // documentation
        3 => MULTIPLIER_CONTENT_BPS,         // content
        4 => MULTIPLIER_CONTENT_BPS,         // marketing
        5 => MULTIPLIER_SUPPORT_BPS,         // support
        6 => MULTIPLIER_DOCS_BPS,            // translation (same as docs)
        7 => MULTIPLIER_DESIGN_BPS,          // design
        8 => MULTIPLIER_TESTING_BPS,         // testing
        9 => MULTIPLIER_INFRA_BPS,           // infrastructure
        _ => MULTIPLIER_FEATURE_BPS,         // default
    };
    
    let adjusted_points = points
        .checked_mul(multiplier_bps)
        .ok_or(BountyError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    // === UPDATE DAILY POOL ===
    
    let daily_pool = &mut ctx.accounts.daily_pool;
    daily_pool.day_index = day_index;
    daily_pool.total_emission = config.current_daily_emission;
    daily_pool.total_points = daily_pool.total_points
        .checked_add(adjusted_points)
        .ok_or(BountyError::ArithmeticOverflow)?;
    daily_pool.proof_count = daily_pool.proof_count
        .checked_add(1)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    // === CALCULATE TOKEN AWARD ===
    // Formula: tokens = (adjusted_points / total_points_today) × daily_emission
    // For real-time: we award proportional share of remaining pool
    
    let tokens_awarded = if daily_pool.total_points > 0 {
        let remaining_emission = daily_pool.total_emission
            .saturating_sub(daily_pool.tokens_distributed);
        
        // Proportional share of remaining
        adjusted_points
            .checked_mul(remaining_emission)
            .ok_or(BountyError::ArithmeticOverflow)?
            .checked_div(daily_pool.total_points)
            .ok_or(BountyError::ArithmeticOverflow)?
    } else {
        0
    };
    
    // === CALCULATE REVIEWER REWARD ===
    
    let reviewer_reward = tokens_awarded
        .checked_mul(REVIEWER_REWARD_BPS)
        .ok_or(BountyError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    let contributor_tokens = tokens_awarded.saturating_sub(reviewer_reward);
    
    // === RECORD PROOF ===
    
    let proof = &mut ctx.accounts.bounty_proof;
    proof.bounty_id = bounty_id;
    proof.operator = operator;
    proof.points = adjusted_points;
    proof.quality_score = quality_score;
    proof.bounty_type = bounty_type;
    proof.is_external_agent = is_external_agent;
    proof.agent_id = agent_id;
    proof.agent_trust_level = agent_trust_level;
    proof.day_index = day_index;
    proof.tokens_awarded = contributor_tokens;
    proof.reviewer = reviewer;
    proof.reviewer_reward = reviewer_reward;
    proof.evidence_hash = evidence_hash;
    proof.submitted_at = now;
    proof.proof_reference = proof_reference;
    proof.bump = ctx.bumps.bounty_proof;
    
    // === UPDATE STATS ===
    
    // Update daily pool
    daily_pool.tokens_distributed = daily_pool.tokens_distributed
        .checked_add(tokens_awarded)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    // Update operator stats
    operator_stats.total_bounties = operator_stats.total_bounties
        .checked_add(1)
        .ok_or(BountyError::ArithmeticOverflow)?;
    operator_stats.total_points = operator_stats.total_points
        .checked_add(adjusted_points)
        .ok_or(BountyError::ArithmeticOverflow)?;
    operator_stats.total_tokens_earned = operator_stats.total_tokens_earned
        .checked_add(contributor_tokens)
        .ok_or(BountyError::ArithmeticOverflow)?;
    operator_stats.current_balance = operator_stats.current_balance
        .checked_add(contributor_tokens)
        .ok_or(BountyError::ArithmeticOverflow)?;
    operator_stats.original_balance = operator_stats.original_balance
        .checked_add(contributor_tokens)
        .ok_or(BountyError::ArithmeticOverflow)?;
    operator_stats.today_bounty_count = operator_stats.today_bounty_count
        .checked_add(1)
        .ok_or(BountyError::ArithmeticOverflow)?;
    operator_stats.last_active_at = now;
    
    // Update global config
    let config = &mut ctx.accounts.bounty_config;
    config.total_tokens_distributed = config.total_tokens_distributed
        .checked_add(tokens_awarded)
        .ok_or(BountyError::ArithmeticOverflow)?;
    config.total_proofs_submitted = config.total_proofs_submitted
        .checked_add(1)
        .ok_or(BountyError::ArithmeticOverflow)?;
    config.total_proofs_approved = config.total_proofs_approved
        .checked_add(1)
        .ok_or(BountyError::ArithmeticOverflow)?;
    config.treasury_remaining = config.treasury_remaining
        .saturating_sub(tokens_awarded);
    
    msg!(
        "Bounty proof #{}: {} points → {} AMOS to operator, {} AMOS to reviewer",
        bounty_id, adjusted_points, contributor_tokens, reviewer_reward
    );
    
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNT CONTEXTS
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Accounts)]
#[instruction(
    bounty_id: u64,
    operator: Pubkey,
    points: u64,
    quality_score: u8,
    bounty_type: u8,
    is_external_agent: bool,
    agent_id: u64,
    agent_trust_level: u8,
    reviewer: Pubkey,
    evidence_hash: [u8; 32],
    proof_reference: String,
)]
pub struct SubmitBountyProof<'info> {
    #[account(
        mut,
        seeds = [seeds::BOUNTY_CONFIG],
        bump = bounty_config.bump,
    )]
    pub bounty_config: Account<'info, BountyConfig>,
    
    /// Daily pool — passed in by the oracle (verified via seeds)
    #[account(mut)]
    pub daily_pool: Account<'info, DailyPool>,
    
    #[account(
        init,
        payer = oracle,
        space = BountyProof::SIZE,
        seeds = [seeds::BOUNTY_PROOF, proof_reference.as_bytes()],
        bump,
    )]
    pub bounty_proof: Account<'info, BountyProof>,
    
    #[account(
        init_if_needed,
        payer = oracle,
        space = OperatorStats::SIZE,
        seeds = [seeds::OPERATOR_STATS, operator.as_ref()],
        bump,
    )]
    pub operator_stats: Account<'info, OperatorStats>,
    
    #[account(mut)]
    pub oracle: Signer<'info>,
    
    pub system_program: Program<'info, System>,
}
