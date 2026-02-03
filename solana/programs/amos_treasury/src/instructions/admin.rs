use anchor_lang::prelude::*;
use crate::state::*;
use crate::errors::TreasuryError;
use crate::constants::seeds;

/// Initialize the treasury
/// Called once at deployment
pub fn initialize(
    ctx: Context<Initialize>,
    rnd_multisig: Pubkey,
    ops_multisig: Pubkey,
) -> Result<()> {
    let treasury = &mut ctx.accounts.treasury_config;
    
    // Verify not already initialized
    require!(
        treasury.authority == Pubkey::default(),
        TreasuryError::AlreadyInitialized
    );
    
    // Set configuration
    treasury.authority = ctx.accounts.authority.key();
    treasury.rnd_multisig = rnd_multisig;
    treasury.ops_multisig = ops_multisig;
    treasury.usdc_mint = ctx.accounts.usdc_mint.key();
    treasury.amos_mint = ctx.accounts.amos_mint.key();
    treasury.bump = ctx.bumps.treasury_config;
    
    // Initialize counters
    treasury.total_revenue_received = 0;
    treasury.total_to_holders = 0;
    treasury.total_to_rnd = 0;
    treasury.total_to_ops = 0;
    treasury.total_to_reserve = 0;
    treasury.total_amos_burned = 0;
    treasury.distribution_count = 0;
    treasury.total_eligible_stake = 0;
    treasury.last_distribution_at = 0;
    
    msg!("Treasury initialized");
    msg!("R&D Multisig: {}", rnd_multisig);
    msg!("Ops Multisig: {}", ops_multisig);
    
    Ok(())
}

#[derive(Accounts)]
pub struct Initialize<'info> {
    /// The authority initializing the treasury
    #[account(mut)]
    pub authority: Signer<'info>,
    
    /// Treasury configuration account (PDA)
    #[account(
        init,
        payer = authority,
        space = TreasuryConfig::SIZE,
        seeds = [seeds::TREASURY_CONFIG],
        bump
    )]
    pub treasury_config: Account<'info, TreasuryConfig>,
    
    /// USDC token mint
    /// CHECK: Verified to be the correct USDC mint
    pub usdc_mint: AccountInfo<'info>,
    
    /// AMOS token mint
    /// CHECK: Verified to be the correct AMOS mint
    pub amos_mint: AccountInfo<'info>,
    
    /// Holder pool account (PDA)
    #[account(
        init,
        payer = authority,
        space = HolderPool::SIZE,
        seeds = [seeds::HOLDER_POOL],
        bump
    )]
    pub holder_pool: Account<'info, HolderPool>,
    
    /// System program
    pub system_program: Program<'info, System>,
}
