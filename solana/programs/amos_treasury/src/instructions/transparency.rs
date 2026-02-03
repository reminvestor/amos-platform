use anchor_lang::prelude::*;
use crate::state::*;
use crate::constants::seeds;
use crate::{TreasuryStats, DistributionRecord};

/// Get current treasury state for dashboard
pub fn get_treasury_state(ctx: Context<GetTreasuryState>) -> Result<TreasuryStats> {
    let treasury = &ctx.accounts.treasury_config;
    let holder_pool = &ctx.accounts.holder_pool;
    
    Ok(TreasuryStats {
        total_revenue_received: treasury.total_revenue_received,
        total_distributed_to_holders: treasury.total_to_holders,
        total_distributed_to_rnd: treasury.total_to_rnd,
        total_distributed_to_ops: treasury.total_to_ops,
        total_to_reserve: treasury.total_to_reserve,
        total_amos_burned: treasury.total_amos_burned,
        holder_pool_balance: holder_pool.balance,
        eligible_stake: treasury.total_eligible_stake,
        distribution_count: treasury.distribution_count,
    })
}

/// Get distribution history
pub fn get_distribution_history(
    ctx: Context<GetDistributionHistory>,
    limit: u8,
) -> Result<Vec<DistributionRecord>> {
    let treasury = &ctx.accounts.treasury_config;
    let mut records = Vec::new();
    
    // This is a simplified implementation
    // In production, you'd iterate through distribution PDAs
    let count = std::cmp::min(limit as u64, treasury.distribution_count);
    
    // Return placeholder for now - actual implementation would
    // read from distribution accounts
    msg!("Returning {} distribution records", count);
    
    Ok(records)
}

#[derive(Accounts)]
pub struct GetTreasuryState<'info> {
    /// Treasury configuration
    #[account(
        seeds = [seeds::TREASURY_CONFIG],
        bump = treasury_config.bump
    )]
    pub treasury_config: Account<'info, TreasuryConfig>,
    
    /// Holder pool state
    #[account(
        seeds = [seeds::HOLDER_POOL],
        bump = holder_pool.bump
    )]
    pub holder_pool: Account<'info, HolderPool>,
}

#[derive(Accounts)]
pub struct GetDistributionHistory<'info> {
    /// Treasury configuration
    #[account(
        seeds = [seeds::TREASURY_CONFIG],
        bump = treasury_config.bump
    )]
    pub treasury_config: Account<'info, TreasuryConfig>,
}
