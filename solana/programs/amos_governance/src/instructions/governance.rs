use anchor_lang::prelude::*;
use crate::state::*;
use crate::errors::GovernanceError;
use crate::constants::seeds;
use crate::GovernanceConfigParams;

#[derive(Accounts)]
pub struct InitializeGovernance<'info> {
    #[account(
        init,
        payer = authority,
        space = GovernanceConfig::LEN,
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    /// The AMOS token mint
    pub amos_mint: Account<'info, anchor_spl::token::Mint>,

    /// Treasury token account for rewards
    #[account(
        init,
        payer = authority,
        seeds = [seeds::TREASURY],
        bump,
        token::mint = amos_mint,
        token::authority = governance_config,
    )]
    pub treasury: Account<'info, anchor_spl::token::TokenAccount>,

    /// Platform authority (deployer)
    #[account(mut)]
    pub authority: Signer<'info>,

    /// Oracle authority for reporting gate results
    /// CHECK: Will be validated by the authority
    pub oracle_authority: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
    pub token_program: Program<'info, anchor_spl::token::Token>,
    pub rent: Sysvar<'info, Rent>,
}

pub fn initialize_governance(
    ctx: Context<InitializeGovernance>,
    config: GovernanceConfigParams,
) -> Result<()> {
    let governance = &mut ctx.accounts.governance_config;
    
    governance.authority = ctx.accounts.authority.key();
    governance.oracle_authority = ctx.accounts.oracle_authority.key();
    governance.amos_mint = ctx.accounts.amos_mint.key();
    governance.treasury = ctx.accounts.treasury.key();
    governance.params = config.into();
    governance.total_proposals = 0;
    governance.total_research_proposals = 0;
    governance.total_rewards_distributed = 0;
    governance.bump = ctx.bumps.governance_config;

    msg!("Governance initialized with authority: {}", governance.authority);
    msg!("Oracle authority: {}", governance.oracle_authority);
    
    Ok(())
}

#[derive(Accounts)]
pub struct UpdateGovernanceParams<'info> {
    #[account(
        mut,
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = authority @ GovernanceError::Unauthorized,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    pub authority: Signer<'info>,
}

pub fn update_governance_params(
    ctx: Context<UpdateGovernanceParams>,
    new_params: GovernanceConfigParams,
) -> Result<()> {
    let governance = &mut ctx.accounts.governance_config;
    
    // Validate params
    require!(
        new_params.bounty_completion_bps + new_params.bounty_ab_success_bps + new_params.bounty_stable_merge_bps == 10000,
        GovernanceError::InvalidGovernanceParams
    );
    
    governance.params = new_params.into();
    
    msg!("Governance parameters updated");
    
    Ok(())
}
