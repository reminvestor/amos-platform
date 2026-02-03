use anchor_lang::prelude::*;
use anchor_lang::solana_program::hash::hash;
use crate::state::*;
use crate::errors::GovernanceError;
use crate::constants::{seeds, MAX_TITLE_LEN, MAX_DESCRIPTION_LEN, MAX_MILESTONES, BPS_DENOMINATOR};

#[derive(Accounts)]
#[instruction(title: String, description: String)]
pub struct SubmitResearchProposal<'info> {
    #[account(
        mut,
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        init,
        payer = researcher,
        space = ResearchProposal::LEN,
        seeds = [seeds::RESEARCH_PROPOSAL, governance_config.total_research_proposals.to_le_bytes().as_ref()],
        bump
    )]
    pub research_proposal: Account<'info, ResearchProposal>,

    #[account(mut)]
    pub researcher: Signer<'info>,

    pub system_program: Program<'info, System>,
}

pub fn submit_research_proposal(
    ctx: Context<SubmitResearchProposal>,
    title: String,
    description: String,
    requested_stipend: u64,
    milestone_count: u8,
) -> Result<()> {
    require!(title.len() <= MAX_TITLE_LEN, GovernanceError::TitleTooLong);
    require!(description.len() <= MAX_DESCRIPTION_LEN, GovernanceError::DescriptionTooLong);
    require!(milestone_count <= MAX_MILESTONES, GovernanceError::TooManyMilestones);

    let governance = &mut ctx.accounts.governance_config;
    let research = &mut ctx.accounts.research_proposal;
    let clock = Clock::get()?;

    research.id = governance.total_research_proposals;
    research.researcher = ctx.accounts.researcher.key();
    research.title_hash = hash(title.as_bytes()).to_bytes();
    research.description_hash = hash(description.as_bytes()).to_bytes();
    research.status = ResearchStatus::Submitted;
    research.requested_stipend = requested_stipend;
    research.approved_stipend = 0;
    research.stipend_paid = 0;
    research.total_milestones = milestone_count;
    research.completed_milestones = 0;
    research.milestone_hashes = [[0u8; 32]; 10];
    research.submitted_at = clock.unix_timestamp;
    research.approved_at = None;
    research.completed_at = None;
    research.graduated_to = None;
    research.bump = ctx.bumps.research_proposal;

    governance.total_research_proposals = governance.total_research_proposals
        .checked_add(1)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    msg!("Research proposal {} submitted", research.id);

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct ApproveResearch<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = oracle_authority @ GovernanceError::UnauthorizedOracle,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::RESEARCH_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = research_proposal.bump,
    )]
    pub research_proposal: Account<'info, ResearchProposal>,

    /// Treasury for stipend payments
    #[account(
        mut,
        seeds = [seeds::TREASURY],
        bump,
        token::mint = governance_config.amos_mint,
    )]
    pub treasury: Account<'info, anchor_spl::token::TokenAccount>,

    /// Researcher's token account for stipend
    #[account(
        mut,
        token::mint = governance_config.amos_mint,
    )]
    pub researcher_token_account: Account<'info, anchor_spl::token::TokenAccount>,

    pub oracle_authority: Signer<'info>,

    pub token_program: Program<'info, anchor_spl::token::Token>,
}

pub fn approve_research(
    ctx: Context<ApproveResearch>,
    _proposal_id: u64,
    approved_stipend: u64,
) -> Result<()> {
    let research = &mut ctx.accounts.research_proposal;
    let governance = &ctx.accounts.governance_config;
    let clock = Clock::get()?;

    require!(
        research.status == ResearchStatus::Submitted,
        GovernanceError::InvalidResearchStatus
    );

    research.status = ResearchStatus::Approved;
    research.approved_stipend = approved_stipend;
    research.approved_at = Some(clock.unix_timestamp);

    // Pay upfront stipend (20% by default)
    let upfront_amount = approved_stipend
        .checked_mul(governance.params.research_stipend_bps as u64)
        .ok_or(GovernanceError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    let seeds = &[seeds::GOVERNANCE_CONFIG, &[governance.bump]];
    let signer_seeds = &[&seeds[..]];

    anchor_spl::token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            anchor_spl::token::Transfer {
                from: ctx.accounts.treasury.to_account_info(),
                to: ctx.accounts.researcher_token_account.to_account_info(),
                authority: ctx.accounts.governance_config.to_account_info(),
            },
            signer_seeds,
        ),
        upfront_amount,
    )?;

    research.stipend_paid = upfront_amount;
    research.status = ResearchStatus::InProgress;

    msg!("Research approved with stipend {}. Upfront payment: {}", approved_stipend, upfront_amount);

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct ReportResearchMilestone<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = oracle_authority @ GovernanceError::UnauthorizedOracle,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::RESEARCH_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = research_proposal.bump,
    )]
    pub research_proposal: Account<'info, ResearchProposal>,

    pub oracle_authority: Signer<'info>,
}

pub fn report_research_milestone(
    ctx: Context<ReportResearchMilestone>,
    _proposal_id: u64,
    milestone_index: u8,
    evidence_hash: [u8; 32],
) -> Result<()> {
    let research = &mut ctx.accounts.research_proposal;
    let clock = Clock::get()?;

    require!(
        research.status == ResearchStatus::InProgress,
        GovernanceError::InvalidResearchStatus
    );
    require!(
        milestone_index < research.total_milestones,
        GovernanceError::InvalidMilestoneIndex
    );
    require!(
        research.milestone_hashes[milestone_index as usize] == [0u8; 32],
        GovernanceError::MilestoneAlreadyCompleted
    );

    research.milestone_hashes[milestone_index as usize] = evidence_hash;
    research.completed_milestones = research.completed_milestones
        .checked_add(1)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    // Check if all milestones complete
    if research.completed_milestones == research.total_milestones {
        research.status = ResearchStatus::Completed;
        research.completed_at = Some(clock.unix_timestamp);
    }

    msg!("Research milestone {} completed ({}/{})", 
        milestone_index, research.completed_milestones, research.total_milestones);

    Ok(())
}

#[derive(Accounts)]
#[instruction(research_proposal_id: u64)]
pub struct GraduateResearch<'info> {
    #[account(
        mut,
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = oracle_authority @ GovernanceError::UnauthorizedOracle,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::RESEARCH_PROPOSAL, research_proposal_id.to_le_bytes().as_ref()],
        bump = research_proposal.bump,
    )]
    pub research_proposal: Account<'info, ResearchProposal>,

    #[account(
        init,
        payer = oracle_authority,
        space = FeatureProposal::LEN,
        seeds = [seeds::FEATURE_PROPOSAL, governance_config.total_proposals.to_le_bytes().as_ref()],
        bump
    )]
    pub feature_proposal: Account<'info, FeatureProposal>,

    /// Treasury for success bonus
    #[account(
        mut,
        seeds = [seeds::TREASURY],
        bump,
        token::mint = governance_config.amos_mint,
    )]
    pub treasury: Account<'info, anchor_spl::token::TokenAccount>,

    /// Researcher's token account for success bonus
    #[account(
        mut,
        token::mint = governance_config.amos_mint,
    )]
    pub researcher_token_account: Account<'info, anchor_spl::token::TokenAccount>,

    #[account(mut)]
    pub oracle_authority: Signer<'info>,

    pub token_program: Program<'info, anchor_spl::token::Token>,
    pub system_program: Program<'info, System>,
}

pub fn graduate_research(
    ctx: Context<GraduateResearch>,
    _research_proposal_id: u64,
    feature_bounty: u64,
) -> Result<()> {
    let clock = Clock::get()?;
    
    // Get values we need before mutable borrows
    let governance_bump = ctx.accounts.governance_config.bump;
    let success_multiplier = ctx.accounts.governance_config.params.research_success_multiplier_bps;
    let feature_id = ctx.accounts.governance_config.total_proposals;
    let governance_info = ctx.accounts.governance_config.to_account_info();

    let research = &mut ctx.accounts.research_proposal;

    require!(
        research.status == ResearchStatus::Completed,
        GovernanceError::InvalidResearchStatus
    );
    require!(
        research.graduated_to.is_none(),
        GovernanceError::ResearchAlreadyGraduated
    );

    // Pay success bonus (80% of remaining stipend)
    let remaining_stipend = research.approved_stipend
        .checked_sub(research.stipend_paid)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    let success_bonus = remaining_stipend
        .checked_mul(success_multiplier as u64)
        .ok_or(GovernanceError::ArithmeticOverflow)?
        .checked_div(BPS_DENOMINATOR)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    let seeds = &[seeds::GOVERNANCE_CONFIG, &[governance_bump]];
    let signer_seeds = &[&seeds[..]];

    anchor_spl::token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            anchor_spl::token::Transfer {
                from: ctx.accounts.treasury.to_account_info(),
                to: ctx.accounts.researcher_token_account.to_account_info(),
                authority: governance_info,
            },
            signer_seeds,
        ),
        success_bonus,
    )?;

    research.stipend_paid = research.stipend_paid
        .checked_add(success_bonus)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    // Create the feature proposal
    let feature = &mut ctx.accounts.feature_proposal;
    let governance = &mut ctx.accounts.governance_config;
    
    feature.id = feature_id;
    feature.proposer = research.researcher;
    feature.builder = Some(research.researcher); // Researcher becomes builder
    feature.title_hash = research.title_hash;
    feature.description_hash = research.description_hash;
    feature.status = crate::ProposalStatus::InDevelopment;
    feature.bounty_amount = feature_bounty;
    feature.bounty_claimed = 0;
    feature.community_votes = 0;
    feature.customer_vote_score = 0;
    feature.customer_request_count = 0;
    feature.submitted_at = clock.unix_timestamp;
    feature.development_started_at = Some(clock.unix_timestamp);
    feature.completed_at = None;
    feature.gates = GateResults::default();
    feature.bump = ctx.bumps.feature_proposal;

    governance.total_proposals = governance.total_proposals
        .checked_add(1)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    // Link research to feature
    research.status = ResearchStatus::Graduated;
    research.graduated_to = Some(feature_id);

    msg!("Research graduated to feature proposal {}. Success bonus: {}", feature_id, success_bonus);

    Ok(())
}
