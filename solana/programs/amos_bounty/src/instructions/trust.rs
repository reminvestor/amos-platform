use anchor_lang::prelude::*;
use crate::state::*;
use crate::constants::*;
use crate::errors::BountyError;

/// Register an external agent's trust record on-chain
/// Called by the platform oracle when an agent first registers
pub fn register_agent_trust(
    ctx: Context<RegisterAgentTrust>,
    agent_id: u64,
    operator: Pubkey,
) -> Result<()> {
    let config = &ctx.accounts.bounty_config;
    require!(
        ctx.accounts.oracle.key() == config.oracle_authority,
        BountyError::InvalidOracle
    );
    
    let record = &mut ctx.accounts.agent_trust;
    record.agent_id = agent_id;
    record.operator = operator;
    record.trust_level = 1;
    record.total_completions = 0;
    record.total_rejections = 0;
    record.reputation_bps = 5000; // Start at 50%
    record.total_tokens_earned = 0;
    record.registered_at = Clock::get()?.unix_timestamp;
    record.last_trust_change_at = Clock::get()?.unix_timestamp;
    record.bump = ctx.bumps.agent_trust;
    
    msg!("Agent {} registered at trust level 1", agent_id);
    
    Ok(())
}

/// Record a bounty completion for an agent (updates stats for trust progression)
pub fn record_agent_completion(
    ctx: Context<RecordAgentCompletion>,
    agent_id: u64,
    approved: bool,
    tokens_earned: u64,
) -> Result<()> {
    let config = &ctx.accounts.bounty_config;
    require!(
        ctx.accounts.oracle.key() == config.oracle_authority,
        BountyError::InvalidOracle
    );
    
    let record = &mut ctx.accounts.agent_trust;
    
    if approved {
        record.total_completions = record.total_completions
            .checked_add(1)
            .ok_or(BountyError::ArithmeticOverflow)?;
        record.total_tokens_earned = record.total_tokens_earned
            .checked_add(tokens_earned)
            .ok_or(BountyError::ArithmeticOverflow)?;
    } else {
        record.total_rejections = record.total_rejections
            .checked_add(1)
            .ok_or(BountyError::ArithmeticOverflow)?;
    }
    
    // Recalculate reputation
    let total = record.total_completions + record.total_rejections;
    if total > 0 {
        record.reputation_bps = record.total_completions
            .checked_mul(BPS_DENOMINATOR)
            .ok_or(BountyError::ArithmeticOverflow)?
            .checked_div(total)
            .ok_or(BountyError::ArithmeticOverflow)?;
    }
    
    msg!(
        "Agent {} completion recorded (approved: {}, reputation: {}bps)",
        agent_id, approved, record.reputation_bps
    );
    
    Ok(())
}

/// Upgrade an agent's trust level (on-chain verification of thresholds)
///
/// The chain enforces the thresholds — the platform can request an upgrade,
/// but only if the on-chain stats meet the requirements.
pub fn upgrade_trust_level(ctx: Context<UpgradeTrustLevel>, agent_id: u64) -> Result<()> {
    let config = &ctx.accounts.bounty_config;
    require!(
        ctx.accounts.oracle.key() == config.oracle_authority,
        BountyError::InvalidOracle
    );
    
    let record = &mut ctx.accounts.agent_trust;
    
    require!(record.trust_level < MAX_TRUST_LEVEL, BountyError::AlreadyMaxTrust);
    
    let next_level = record.trust_level + 1;
    
    // Verify thresholds ON-CHAIN (platform can't fake these)
    let (min_completions, min_reputation) = match next_level {
        2 => (TRUST_2_MIN_COMPLETIONS, TRUST_2_MIN_REPUTATION_BPS),
        3 => (TRUST_3_MIN_COMPLETIONS, TRUST_3_MIN_REPUTATION_BPS),
        4 => (TRUST_4_MIN_COMPLETIONS, TRUST_4_MIN_REPUTATION_BPS),
        5 => (TRUST_5_MIN_COMPLETIONS, TRUST_5_MIN_REPUTATION_BPS),
        _ => return Err(BountyError::AlreadyMaxTrust.into()),
    };
    
    require!(
        record.total_completions >= min_completions,
        BountyError::TrustUpgradeNotEligible
    );
    require!(
        record.reputation_bps >= min_reputation,
        BountyError::TrustUpgradeNotEligible
    );
    
    record.trust_level = next_level;
    record.last_trust_change_at = Clock::get()?.unix_timestamp;
    
    msg!(
        "Agent {} upgraded to trust level {} (completions: {}, reputation: {}bps)",
        agent_id, next_level, record.total_completions, record.reputation_bps
    );
    
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNT CONTEXTS
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Accounts)]
#[instruction(agent_id: u64, operator: Pubkey)]
pub struct RegisterAgentTrust<'info> {
    #[account(
        seeds = [seeds::BOUNTY_CONFIG],
        bump = bounty_config.bump,
    )]
    pub bounty_config: Account<'info, BountyConfig>,
    
    #[account(
        init,
        payer = oracle,
        space = AgentTrustRecord::SIZE,
        seeds = [seeds::AGENT_TRUST, &agent_id.to_le_bytes()],
        bump,
    )]
    pub agent_trust: Account<'info, AgentTrustRecord>,
    
    #[account(mut)]
    pub oracle: Signer<'info>,
    
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(agent_id: u64)]
pub struct RecordAgentCompletion<'info> {
    #[account(
        seeds = [seeds::BOUNTY_CONFIG],
        bump = bounty_config.bump,
    )]
    pub bounty_config: Account<'info, BountyConfig>,
    
    #[account(
        mut,
        seeds = [seeds::AGENT_TRUST, &agent_id.to_le_bytes()],
        bump = agent_trust.bump,
    )]
    pub agent_trust: Account<'info, AgentTrustRecord>,
    
    pub oracle: Signer<'info>,
}

#[derive(Accounts)]
#[instruction(agent_id: u64)]
pub struct UpgradeTrustLevel<'info> {
    #[account(
        seeds = [seeds::BOUNTY_CONFIG],
        bump = bounty_config.bump,
    )]
    pub bounty_config: Account<'info, BountyConfig>,
    
    #[account(
        mut,
        seeds = [seeds::AGENT_TRUST, &agent_id.to_le_bytes()],
        bump = agent_trust.bump,
    )]
    pub agent_trust: Account<'info, AgentTrustRecord>,
    
    pub oracle: Signer<'info>,
}
