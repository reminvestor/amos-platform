use anchor_lang::prelude::*;
use crate::state::*;
use crate::constants::*;
use crate::errors::BountyError;

/// Initialize the bounty program configuration
/// Called once at program deployment
pub fn initialize(
    ctx: Context<Initialize>,
    oracle_authority: Pubkey,
) -> Result<()> {
    let config = &mut ctx.accounts.bounty_config;
    
    require!(!config.total_proofs_submitted > 0, BountyError::AlreadyInitialized);
    
    config.oracle_authority = oracle_authority;
    config.amos_mint = ctx.accounts.amos_mint.key();
    config.program_start_at = Clock::get()?.unix_timestamp;
    config.current_halving_epoch = 0;
    config.current_daily_emission = INITIAL_DAILY_EMISSION;
    config.treasury_remaining = TREASURY_ALLOCATION;
    config.current_decay_rate_bps = DEFAULT_DECAY_RATE_BPS;
    config.decay_rate_updated_at = Clock::get()?.unix_timestamp;
    config.bump = ctx.bumps.bounty_config;
    
    msg!("AMOS Bounty Program initialized");
    msg!("Oracle: {}", oracle_authority);
    msg!("Daily emission: {} AMOS", INITIAL_DAILY_EMISSION);
    msg!("Treasury pool: {} AMOS", TREASURY_ALLOCATION);
    
    Ok(())
}

/// Update the decay rate (oracle only, within allowed range)
/// The platform calculates the appropriate rate based on health metrics
/// but the chain enforces the min/max bounds
pub fn update_decay_rate(
    ctx: Context<UpdateDecayRate>,
    new_rate_bps: u64,
) -> Result<()> {
    require!(
        new_rate_bps >= MIN_DECAY_RATE_BPS && new_rate_bps <= MAX_DECAY_RATE_BPS,
        BountyError::DecayRateOutOfRange
    );
    
    let config = &mut ctx.accounts.bounty_config;
    require!(
        ctx.accounts.authority.key() == config.oracle_authority,
        BountyError::Unauthorized
    );
    
    config.current_decay_rate_bps = new_rate_bps;
    config.decay_rate_updated_at = Clock::get()?.unix_timestamp;
    
    msg!("Decay rate updated to {}bps ({}%)", new_rate_bps, new_rate_bps as f64 / 100.0);
    
    Ok(())
}

/// Advance halving epoch when enough time has passed
pub fn advance_halving(ctx: Context<AdvanceHalving>) -> Result<()> {
    let config = &mut ctx.accounts.bounty_config;
    let now = Clock::get()?.unix_timestamp;
    
    let days_since_start = ((now - config.program_start_at) / 86400) as u64;
    let expected_epoch = (days_since_start / HALVING_INTERVAL_DAYS).min(MAX_HALVING_EPOCHS) as u8;
    
    require!(
        expected_epoch > config.current_halving_epoch,
        BountyError::InvalidHalvingEpoch
    );
    
    config.current_halving_epoch = expected_epoch;
    
    // Calculate new emission: initial / 2^epoch, with floor
    let new_emission = INITIAL_DAILY_EMISSION
        .checked_div(1u64.checked_shl(expected_epoch as u32).unwrap_or(1024))
        .unwrap_or(MINIMUM_DAILY_EMISSION)
        .max(MINIMUM_DAILY_EMISSION);
    
    config.current_daily_emission = new_emission;
    
    msg!("Halving epoch advanced to {}. New daily emission: {} AMOS", expected_epoch, new_emission);
    
    Ok(())
}

// ═══════════════════════════════════════════════════════════════════════════
// ACCOUNT CONTEXTS
// ═══════════════════════════════════════════════════════════════════════════

#[derive(Accounts)]
pub struct Initialize<'info> {
    #[account(
        init,
        payer = authority,
        space = BountyConfig::SIZE,
        seeds = [seeds::BOUNTY_CONFIG],
        bump,
    )]
    pub bounty_config: Account<'info, BountyConfig>,
    
    /// CHECK: AMOS token mint
    pub amos_mint: AccountInfo<'info>,
    
    #[account(mut)]
    pub authority: Signer<'info>,
    
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct UpdateDecayRate<'info> {
    #[account(
        mut,
        seeds = [seeds::BOUNTY_CONFIG],
        bump = bounty_config.bump,
    )]
    pub bounty_config: Account<'info, BountyConfig>,
    
    pub authority: Signer<'info>,
}

#[derive(Accounts)]
pub struct AdvanceHalving<'info> {
    #[account(
        mut,
        seeds = [seeds::BOUNTY_CONFIG],
        bump = bounty_config.bump,
    )]
    pub bounty_config: Account<'info, BountyConfig>,
    
    /// Anyone can call this — it's a public good
    pub caller: Signer<'info>,
}
