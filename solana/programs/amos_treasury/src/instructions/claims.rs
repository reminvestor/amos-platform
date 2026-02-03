use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer};
use crate::state::*;
use crate::errors::TreasuryError;
use crate::constants::*;
use crate::constants::seeds;

/// Register a stake for revenue eligibility
/// 
/// Users must register their stake on-chain to be eligible for revenue share.
/// The stake amount is synced from the platform's internal ledger.
pub fn register_stake(
    ctx: Context<RegisterStake>,
    amount: u64,
) -> Result<()> {
    require!(amount >= MIN_STAKE_AMOUNT, TreasuryError::InsufficientStake);
    
    let stake = &mut ctx.accounts.stake_record;
    let treasury = &mut ctx.accounts.treasury_config;
    let clock = Clock::get()?;
    
    stake.owner = ctx.accounts.owner.key();
    stake.amount = amount;
    stake.registered_at = clock.unix_timestamp;
    stake.updated_at = clock.unix_timestamp;
    stake.total_claimed = 0;
    stake.last_claim_at = 0;
    stake.unclaimed_revenue = 0;
    stake.bump = ctx.bumps.stake_record;
    
    // Update total eligible stake
    treasury.total_eligible_stake = treasury.total_eligible_stake
        .checked_add(amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    msg!("Stake registered: {} AMOS for {}", amount, ctx.accounts.owner.key());
    
    Ok(())
}

/// Update stake amount
/// 
/// Called when the platform syncs stake changes (decay, new earnings, etc.)
pub fn update_stake(
    ctx: Context<UpdateStake>,
    new_amount: u64,
) -> Result<()> {
    let stake = &mut ctx.accounts.stake_record;
    let treasury = &mut ctx.accounts.treasury_config;
    let clock = Clock::get()?;
    
    let old_amount = stake.amount;
    
    // Update total eligible stake
    if new_amount > old_amount {
        let diff = new_amount.checked_sub(old_amount)
            .ok_or(TreasuryError::ArithmeticOverflow)?;
        treasury.total_eligible_stake = treasury.total_eligible_stake
            .checked_add(diff)
            .ok_or(TreasuryError::ArithmeticOverflow)?;
    } else {
        let diff = old_amount.checked_sub(new_amount)
            .ok_or(TreasuryError::ArithmeticOverflow)?;
        treasury.total_eligible_stake = treasury.total_eligible_stake
            .saturating_sub(diff);
    }
    
    stake.amount = new_amount;
    stake.updated_at = clock.unix_timestamp;
    
    msg!("Stake updated: {} -> {} AMOS", old_amount, new_amount);
    
    Ok(())
}

/// Claim accumulated revenue share
/// 
/// This is the user-facing claim function.
/// NO APPROVAL NEEDED - if you're eligible, you can claim.
/// 
/// Eligibility requirements:
/// 1. Stake >= MIN_STAKE_AMOUNT (100 AMOS)
/// 2. Stake held for >= MIN_STAKE_DAYS (30 days)
pub fn claim_revenue(ctx: Context<ClaimRevenue>) -> Result<()> {
    let stake = &ctx.accounts.stake_record;
    let treasury = &ctx.accounts.treasury_config;
    let holder_pool = &mut ctx.accounts.holder_pool;
    let clock = Clock::get()?;
    
    // Verify eligibility: minimum stake
    require!(
        stake.amount >= MIN_STAKE_AMOUNT,
        TreasuryError::InsufficientStake
    );
    
    // Verify eligibility: stake duration
    let stake_age_days = (clock.unix_timestamp - stake.registered_at) / 86400;
    require!(
        stake_age_days >= MIN_STAKE_DAYS as i64,
        TreasuryError::StakeTooRecent
    );
    
    // Calculate share: (your_stake / total_stake) * pool_balance
    require!(
        treasury.total_eligible_stake > 0,
        TreasuryError::NoRevenueToClaim
    );
    
    let share_bps = stake.amount
        .checked_mul(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(treasury.total_eligible_stake)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    let payout = holder_pool.balance
        .checked_mul(share_bps)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    require!(payout > 0, TreasuryError::NoRevenueToClaim);
    require!(payout <= holder_pool.balance, TreasuryError::InsufficientPoolBalance);
    
    // Execute transfer
    let treasury_seeds = &[
        seeds::TREASURY_CONFIG,
        &[treasury.bump],
    ];
    let signer_seeds = &[&treasury_seeds[..]];
    
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.holder_pool_token.to_account_info(),
                to: ctx.accounts.user_token.to_account_info(),
                authority: ctx.accounts.treasury_config.to_account_info(),
            },
            signer_seeds,
        ),
        payout,
    )?;
    
    // Update state
    let stake = &mut ctx.accounts.stake_record;
    let holder_pool = &mut ctx.accounts.holder_pool;
    
    stake.total_claimed = stake.total_claimed
        .checked_add(payout)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    stake.last_claim_at = clock.unix_timestamp;
    stake.unclaimed_revenue = 0;
    
    holder_pool.balance = holder_pool.balance
        .checked_sub(payout)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    holder_pool.total_claimed = holder_pool.total_claimed
        .checked_add(payout)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    holder_pool.claim_count = holder_pool.claim_count
        .checked_add(1)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    msg!("=== REVENUE CLAIMED ===");
    msg!("User: {}", ctx.accounts.owner.key());
    msg!("Stake: {} AMOS", stake.amount);
    msg!("Share: {} bps ({}%)", share_bps, share_bps as f64 / 100.0);
    msg!("Payout: {} USDC", payout);
    
    Ok(())
}

/// Get claimable amount (read-only)
pub fn get_claimable_amount(ctx: Context<GetClaimable>) -> Result<u64> {
    let stake = &ctx.accounts.stake_record;
    let treasury = &ctx.accounts.treasury_config;
    let holder_pool = &ctx.accounts.holder_pool;
    let clock = Clock::get()?;
    
    // Check eligibility
    if stake.amount < MIN_STAKE_AMOUNT {
        return Ok(0);
    }
    
    let stake_age_days = (clock.unix_timestamp - stake.registered_at) / 86400;
    if stake_age_days < MIN_STAKE_DAYS as i64 {
        return Ok(0);
    }
    
    if treasury.total_eligible_stake == 0 {
        return Ok(0);
    }
    
    // Calculate share
    let share_bps = stake.amount
        .checked_mul(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(treasury.total_eligible_stake)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    let payout = holder_pool.balance
        .checked_mul(share_bps)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    Ok(payout)
}

#[derive(Accounts)]
pub struct RegisterStake<'info> {
    /// Stake owner
    #[account(mut)]
    pub owner: Signer<'info>,
    
    /// Stake record (PDA)
    #[account(
        init,
        payer = owner,
        space = StakeRecord::SIZE,
        seeds = [seeds::STAKE_RECORD, owner.key().as_ref()],
        bump
    )]
    pub stake_record: Account<'info, StakeRecord>,
    
    /// Treasury configuration
    #[account(
        mut,
        seeds = [seeds::TREASURY_CONFIG],
        bump = treasury_config.bump
    )]
    pub treasury_config: Account<'info, TreasuryConfig>,
    
    /// System program
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateStake<'info> {
    /// Oracle/platform authority
    pub authority: Signer<'info>,
    
    /// Stake record
    #[account(
        mut,
        seeds = [seeds::STAKE_RECORD, stake_record.owner.as_ref()],
        bump = stake_record.bump
    )]
    pub stake_record: Account<'info, StakeRecord>,
    
    /// Treasury configuration
    #[account(
        mut,
        seeds = [seeds::TREASURY_CONFIG],
        bump = treasury_config.bump
    )]
    pub treasury_config: Account<'info, TreasuryConfig>,
}

#[derive(Accounts)]
pub struct ClaimRevenue<'info> {
    /// Stake owner claiming revenue
    #[account(mut)]
    pub owner: Signer<'info>,
    
    /// Stake record
    #[account(
        mut,
        seeds = [seeds::STAKE_RECORD, owner.key().as_ref()],
        bump = stake_record.bump,
        constraint = stake_record.owner == owner.key() @ TreasuryError::Unauthorized
    )]
    pub stake_record: Account<'info, StakeRecord>,
    
    /// Treasury configuration
    #[account(
        seeds = [seeds::TREASURY_CONFIG],
        bump = treasury_config.bump
    )]
    pub treasury_config: Account<'info, TreasuryConfig>,
    
    /// Holder pool state
    #[account(
        mut,
        seeds = [seeds::HOLDER_POOL],
        bump = holder_pool.bump
    )]
    pub holder_pool: Account<'info, HolderPool>,
    
    /// Holder pool token account
    #[account(mut)]
    pub holder_pool_token: Account<'info, TokenAccount>,
    
    /// User's USDC token account (destination)
    #[account(mut)]
    pub user_token: Account<'info, TokenAccount>,
    
    /// Token program
    pub token_program: Program<'info, Token>,
}

#[derive(Accounts)]
pub struct GetClaimable<'info> {
    /// Stake record
    #[account(
        seeds = [seeds::STAKE_RECORD, stake_record.owner.as_ref()],
        bump = stake_record.bump
    )]
    pub stake_record: Account<'info, StakeRecord>,
    
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
