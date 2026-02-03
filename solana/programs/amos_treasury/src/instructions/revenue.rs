use anchor_lang::prelude::*;
use anchor_spl::token::{self, Token, TokenAccount, Transfer, Burn};
use crate::state::*;
use crate::errors::TreasuryError;
use crate::constants::*;
use crate::constants::seeds;

/// Receive USDC revenue and immediately split
/// 
/// This is THE CORE FUNCTION of the treasury program.
/// It implements the IMMUTABLE 50/30/10/10 split.
/// 
/// Flow:
/// 1. Receive USDC from payment processor
/// 2. Calculate splits using CONSTANT percentages
/// 3. Transfer to each destination in ONE ATOMIC TRANSACTION
/// 4. Log distribution for transparency
pub fn receive_revenue(
    ctx: Context<ReceiveRevenue>,
    amount: u64,
    payment_reference: String,
) -> Result<()> {
    require!(amount > 0, TreasuryError::InvalidAmount);
    require!(payment_reference.len() <= 64, TreasuryError::PaymentReferenceTooLong);
    
    // ═══════════════════════════════════════════════════════════════════════════
    // CALCULATE SPLITS USING IMMUTABLE CONSTANTS
    // These percentages are compiled into the program binary
    // ═══════════════════════════════════════════════════════════════════════════
    
    let holder_amount = amount
        .checked_mul(HOLDER_SHARE_BPS)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    let rnd_amount = amount
        .checked_mul(RND_SHARE_BPS)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    let ops_amount = amount
        .checked_mul(OPS_SHARE_BPS)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    // Reserve gets the remainder (handles rounding)
    let reserve_amount = amount
        .checked_sub(holder_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_sub(rnd_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_sub(ops_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // EXECUTE TRANSFERS (ALL IN ONE ATOMIC TRANSACTION)
    // Either all succeed or all fail - no partial states
    // ═══════════════════════════════════════════════════════════════════════════
    
    // Transfer to holder pool
    let treasury_seeds = &[
        seeds::TREASURY_CONFIG,
        &[ctx.accounts.treasury_config.bump],
    ];
    let signer_seeds = &[&treasury_seeds[..]];
    
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.revenue_source.to_account_info(),
                to: ctx.accounts.holder_pool_token.to_account_info(),
                authority: ctx.accounts.treasury_config.to_account_info(),
            },
            signer_seeds,
        ),
        holder_amount,
    )?;
    
    // Transfer to R&D multisig
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.revenue_source.to_account_info(),
                to: ctx.accounts.rnd_token.to_account_info(),
                authority: ctx.accounts.treasury_config.to_account_info(),
            },
            signer_seeds,
        ),
        rnd_amount,
    )?;
    
    // Transfer to Operations multisig
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.revenue_source.to_account_info(),
                to: ctx.accounts.ops_token.to_account_info(),
                authority: ctx.accounts.treasury_config.to_account_info(),
            },
            signer_seeds,
        ),
        ops_amount,
    )?;
    
    // Transfer to Reserve (DAO-controlled)
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.revenue_source.to_account_info(),
                to: ctx.accounts.reserve_token.to_account_info(),
                authority: ctx.accounts.treasury_config.to_account_info(),
            },
            signer_seeds,
        ),
        reserve_amount,
    )?;
    
    // ═══════════════════════════════════════════════════════════════════════════
    // UPDATE STATE AND LOG
    // ═══════════════════════════════════════════════════════════════════════════
    
    let treasury = &mut ctx.accounts.treasury_config;
    let holder_pool = &mut ctx.accounts.holder_pool;
    let distribution = &mut ctx.accounts.distribution;
    
    // Update treasury totals
    treasury.total_revenue_received = treasury.total_revenue_received
        .checked_add(amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    treasury.total_to_holders = treasury.total_to_holders
        .checked_add(holder_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    treasury.total_to_rnd = treasury.total_to_rnd
        .checked_add(rnd_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    treasury.total_to_ops = treasury.total_to_ops
        .checked_add(ops_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    treasury.total_to_reserve = treasury.total_to_reserve
        .checked_add(reserve_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    treasury.distribution_count = treasury.distribution_count
        .checked_add(1)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    treasury.last_distribution_at = Clock::get()?.unix_timestamp;
    
    // Update holder pool
    holder_pool.balance = holder_pool.balance
        .checked_add(holder_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    holder_pool.total_deposited = holder_pool.total_deposited
        .checked_add(holder_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    // Record distribution for transparency
    distribution.index = treasury.distribution_count;
    distribution.timestamp = Clock::get()?.unix_timestamp;
    distribution.total_amount = amount;
    distribution.holder_amount = holder_amount;
    distribution.rnd_amount = rnd_amount;
    distribution.ops_amount = ops_amount;
    distribution.reserve_amount = reserve_amount;
    distribution.amos_burned = 0;
    distribution.payment_reference = payment_reference.clone();
    distribution.payment_type = 0; // USDC
    distribution.bump = ctx.bumps.distribution;
    
    // Emit event for off-chain indexing
    msg!("=== REVENUE RECEIVED ===");
    msg!("Amount: {} USDC", amount);
    msg!("Holder Pool: {} (50%)", holder_amount);
    msg!("R&D: {} (30%)", rnd_amount);
    msg!("Operations: {} (10%)", ops_amount);
    msg!("Reserve: {} (10%)", reserve_amount);
    msg!("Reference: {}", payment_reference);
    
    Ok(())
}

/// Receive AMOS token payment
/// 
/// When users pay directly in AMOS:
/// - 50% is BURNED (permanently removed from supply)
/// - 25% goes to holder pool
/// - 25% goes to operations
pub fn receive_amos_payment(
    ctx: Context<ReceiveAmosPayment>,
    amount: u64,
    payment_reference: String,
) -> Result<()> {
    require!(amount > 0, TreasuryError::InvalidAmount);
    require!(payment_reference.len() <= 64, TreasuryError::PaymentReferenceTooLong);
    
    // Calculate splits
    let burn_amount = amount
        .checked_mul(AMOS_BURN_BPS)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    let holder_amount = amount
        .checked_mul(AMOS_HOLDER_BPS)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    let ops_amount = amount
        .checked_sub(burn_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?
        .checked_sub(holder_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    let treasury_seeds = &[
        seeds::TREASURY_CONFIG,
        &[ctx.accounts.treasury_config.bump],
    ];
    let signer_seeds = &[&treasury_seeds[..]];
    
    // BURN 50% - permanently removed from existence
    token::burn(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Burn {
                mint: ctx.accounts.amos_mint.to_account_info(),
                from: ctx.accounts.amos_source.to_account_info(),
                authority: ctx.accounts.treasury_config.to_account_info(),
            },
            signer_seeds,
        ),
        burn_amount,
    )?;
    
    // Transfer to holder pool
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.amos_source.to_account_info(),
                to: ctx.accounts.amos_holder_pool.to_account_info(),
                authority: ctx.accounts.treasury_config.to_account_info(),
            },
            signer_seeds,
        ),
        holder_amount,
    )?;
    
    // Transfer to operations
    token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            Transfer {
                from: ctx.accounts.amos_source.to_account_info(),
                to: ctx.accounts.amos_ops.to_account_info(),
                authority: ctx.accounts.treasury_config.to_account_info(),
            },
            signer_seeds,
        ),
        ops_amount,
    )?;
    
    // Update state
    let treasury = &mut ctx.accounts.treasury_config;
    treasury.total_amos_burned = treasury.total_amos_burned
        .checked_add(burn_amount)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    treasury.distribution_count = treasury.distribution_count
        .checked_add(1)
        .ok_or(TreasuryError::ArithmeticOverflow)?;
    
    msg!("=== AMOS PAYMENT RECEIVED ===");
    msg!("Amount: {} AMOS", amount);
    msg!("BURNED: {} (50%)", burn_amount);
    msg!("Holder Pool: {} (25%)", holder_amount);
    msg!("Operations: {} (25%)", ops_amount);
    msg!("Reference: {}", payment_reference);
    
    Ok(())
}

#[derive(Accounts)]
#[instruction(amount: u64, payment_reference: String)]
pub struct ReceiveRevenue<'info> {
    /// Treasury configuration
    #[account(
        mut,
        seeds = [seeds::TREASURY_CONFIG],
        bump = treasury_config.bump
    )]
    pub treasury_config: Account<'info, TreasuryConfig>,
    
    /// Source of USDC revenue
    #[account(mut)]
    pub revenue_source: Account<'info, TokenAccount>,
    
    /// Holder pool token account
    #[account(mut)]
    pub holder_pool_token: Account<'info, TokenAccount>,
    
    /// Holder pool state
    #[account(
        mut,
        seeds = [seeds::HOLDER_POOL],
        bump = holder_pool.bump
    )]
    pub holder_pool: Account<'info, HolderPool>,
    
    /// R&D multisig token account
    #[account(mut)]
    pub rnd_token: Account<'info, TokenAccount>,
    
    /// Operations multisig token account
    #[account(mut)]
    pub ops_token: Account<'info, TokenAccount>,
    
    /// Reserve token account
    #[account(mut)]
    pub reserve_token: Account<'info, TokenAccount>,
    
    /// Distribution record
    #[account(
        init,
        payer = payer,
        space = Distribution::SIZE,
        seeds = [seeds::DISTRIBUTION, &treasury_config.distribution_count.to_le_bytes()],
        bump
    )]
    pub distribution: Account<'info, Distribution>,
    
    /// Payer for account creation
    #[account(mut)]
    pub payer: Signer<'info>,
    
    /// Token program
    pub token_program: Program<'info, Token>,
    
    /// System program
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(amount: u64, payment_reference: String)]
pub struct ReceiveAmosPayment<'info> {
    /// Treasury configuration
    #[account(
        mut,
        seeds = [seeds::TREASURY_CONFIG],
        bump = treasury_config.bump
    )]
    pub treasury_config: Account<'info, TreasuryConfig>,
    
    /// AMOS token mint (for burning)
    #[account(mut)]
    pub amos_mint: Account<'info, anchor_spl::token::Mint>,
    
    /// Source of AMOS tokens
    #[account(mut)]
    pub amos_source: Account<'info, TokenAccount>,
    
    /// AMOS holder pool token account
    #[account(mut)]
    pub amos_holder_pool: Account<'info, TokenAccount>,
    
    /// AMOS operations token account
    #[account(mut)]
    pub amos_ops: Account<'info, TokenAccount>,
    
    /// Token program
    pub token_program: Program<'info, Token>,
}
