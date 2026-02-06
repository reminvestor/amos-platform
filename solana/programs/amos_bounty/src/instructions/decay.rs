use anchor_lang::prelude::*;
use crate::state::*;
use crate::constants::*;
use crate::errors::BountyError;

/// Apply decay to an inactive operator's stake
///
/// Anyone can call this for any operator (it's a public good).
/// Decay only applies after the grace period (90 days of inactivity).
/// Decayed tokens are split: 10% burned, 90% recycled to treasury.
///
/// The decay rate is dynamic (set by oracle within 2-25% range),
/// but the bounds and formula are IMMUTABLE on-chain.
pub fn apply_decay(ctx: Context<ApplyDecay>) -> Result<()> {
    let config = &mut ctx.accounts.bounty_config;
    let stats = &mut ctx.accounts.operator_stats;
    let now = Clock::get()?.unix_timestamp;
    
    // Check grace period
    let days_inactive = ((now - stats.last_active_at) / 86400) as u64;
    require!(
        days_inactive > DECAY_GRACE_PERIOD_DAYS,
        BountyError::WithinGracePeriod
    );
    
    // Check if already at floor
    let floor_amount = stats.original_balance
        .checked_mul(DECAY_FLOOR_BPS)
        .ok_or(BountyError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    require!(stats.current_balance > floor_amount, BountyError::AtDecayFloor);
    
    // Calculate daily decay
    // Annual rate → daily: daily_rate = annual_rate / 365
    let daily_decay_amount = stats.current_balance
        .checked_mul(config.current_decay_rate_bps)
        .ok_or(BountyError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR * 365)
        .ok_or(BountyError::ArithmeticOverflow)?
        .max(1); // At least 1 token decayed per day
    
    // Don't decay below floor
    let new_balance = stats.current_balance
        .saturating_sub(daily_decay_amount)
        .max(floor_amount);
    
    let actual_decay = stats.current_balance - new_balance;
    
    if actual_decay == 0 {
        return Ok(());
    }
    
    // Split decay: burn portion + recycle to treasury
    let burn_amount = actual_decay
        .checked_mul(DECAY_BURN_PORTION_BPS)
        .ok_or(BountyError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    let recycle_amount = actual_decay.saturating_sub(burn_amount);
    
    // Update operator balance
    stats.current_balance = new_balance;
    stats.total_decayed = stats.total_decayed
        .checked_add(actual_decay)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    // Update global stats
    config.total_decayed = config.total_decayed
        .checked_add(actual_decay)
        .ok_or(BountyError::ArithmeticOverflow)?;
    config.total_decay_burned = config.total_decay_burned
        .checked_add(burn_amount)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    // Recycle to treasury (available for future emissions)
    config.treasury_remaining = config.treasury_remaining
        .checked_add(recycle_amount)
        .ok_or(BountyError::ArithmeticOverflow)?;
    
    msg!(
        "Decay applied to {}: {} AMOS decayed ({} burned, {} recycled). Balance: {} → {}",
        stats.operator,
        actual_decay,
        burn_amount,
        recycle_amount,
        stats.current_balance + actual_decay,
        stats.current_balance
    );
    
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNT CONTEXT
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Accounts)]
pub struct ApplyDecay<'info> {
    #[account(
        mut,
        seeds = [seeds::BOUNTY_CONFIG],
        bump = bounty_config.bump,
    )]
    pub bounty_config: Account<'info, BountyConfig>,
    
    #[account(mut)]
    pub operator_stats: Account<'info, OperatorStats>,
    
    /// Anyone can trigger decay — it's a public good
    pub caller: Signer<'info>,
}
