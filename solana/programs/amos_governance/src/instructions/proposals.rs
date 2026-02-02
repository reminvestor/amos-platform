use anchor_lang::prelude::*;
use anchor_lang::solana_program::hash::hash;
use crate::state::*;
use crate::errors::GovernanceError;
use crate::constants::{seeds, MAX_TITLE_LEN, MAX_DESCRIPTION_LEN, MAX_CUSTOMER_REQUESTS};
use crate::ProposalStatus;

#[derive(Accounts)]
#[instruction(title: String, description: String)]
pub struct SubmitFeatureProposal<'info> {
    #[account(
        mut,
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        init,
        payer = proposer,
        space = FeatureProposal::LEN,
        seeds = [seeds::FEATURE_PROPOSAL, governance_config.total_proposals.to_le_bytes().as_ref()],
        bump
    )]
    pub proposal: Account<'info, FeatureProposal>,

    #[account(mut)]
    pub proposer: Signer<'info>,

    pub system_program: Program<'info, System>,
}

pub fn submit_feature_proposal(
    ctx: Context<SubmitFeatureProposal>,
    title: String,
    description: String,
    estimated_bounty: u64,
    customer_request_ids: Vec<u64>,
) -> Result<()> {
    require!(title.len() <= MAX_TITLE_LEN, GovernanceError::TitleTooLong);
    require!(description.len() <= MAX_DESCRIPTION_LEN, GovernanceError::DescriptionTooLong);
    require!(customer_request_ids.len() <= MAX_CUSTOMER_REQUESTS, GovernanceError::TooManyCustomerRequests);

    let governance = &mut ctx.accounts.governance_config;
    let proposal = &mut ctx.accounts.proposal;
    let clock = Clock::get()?;

    proposal.id = governance.total_proposals;
    proposal.proposer = ctx.accounts.proposer.key();
    proposal.builder = None;
    proposal.title_hash = hash(title.as_bytes()).to_bytes();
    proposal.description_hash = hash(description.as_bytes()).to_bytes();
    proposal.status = ProposalStatus::Submitted;
    proposal.bounty_amount = estimated_bounty;
    proposal.bounty_claimed = 0;
    proposal.community_votes = 0;
    proposal.customer_vote_score = 0;
    proposal.customer_request_count = customer_request_ids.len() as u16;
    proposal.submitted_at = clock.unix_timestamp;
    proposal.development_started_at = None;
    proposal.completed_at = None;
    proposal.gates = GateResults::default();
    proposal.bump = ctx.bumps.proposal;

    governance.total_proposals = governance.total_proposals
        .checked_add(1)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    msg!("Feature proposal {} submitted: {:?}", proposal.id, proposal.title_hash);

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct VoteForFeature<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,

    #[account(
        init,
        payer = voter,
        space = VoteRecord::LEN,
        seeds = [seeds::VOTE_RECORD, proposal_id.to_le_bytes().as_ref(), voter.key().as_ref()],
        bump
    )]
    pub vote_record: Account<'info, VoteRecord>,

    /// Voter's AMOS token account
    #[account(
        mut,
        token::mint = governance_config.amos_mint,
        token::authority = voter,
    )]
    pub voter_token_account: Account<'info, anchor_spl::token::TokenAccount>,

    /// Escrow account for locked votes
    #[account(
        mut,
        seeds = [seeds::TREASURY],
        bump,
        token::mint = governance_config.amos_mint,
    )]
    pub vote_escrow: Account<'info, anchor_spl::token::TokenAccount>,

    #[account(mut)]
    pub voter: Signer<'info>,

    pub token_program: Program<'info, anchor_spl::token::Token>,
    pub system_program: Program<'info, System>,
}

pub fn vote_for_feature(
    ctx: Context<VoteForFeature>,
    proposal_id: u64,
    vote_amount: u64,
) -> Result<()> {
    require!(vote_amount > 0, GovernanceError::InsufficientVoteAmount);
    
    let proposal = &mut ctx.accounts.proposal;
    require!(
        proposal.status == ProposalStatus::Submitted || 
        proposal.status == ProposalStatus::InDevelopment,
        GovernanceError::InvalidProposalStatus
    );

    let vote_record = &mut ctx.accounts.vote_record;
    let clock = Clock::get()?;

    // Transfer tokens to escrow
    anchor_spl::token::transfer(
        CpiContext::new(
            ctx.accounts.token_program.to_account_info(),
            anchor_spl::token::Transfer {
                from: ctx.accounts.voter_token_account.to_account_info(),
                to: ctx.accounts.vote_escrow.to_account_info(),
                authority: ctx.accounts.voter.to_account_info(),
            },
        ),
        vote_amount,
    )?;

    // Record the vote
    vote_record.proposal_id = proposal_id;
    vote_record.voter = ctx.accounts.voter.key();
    vote_record.vote_amount = vote_amount;
    vote_record.voted_at = clock.unix_timestamp;
    vote_record.withdrawn = false;
    vote_record.bump = ctx.bumps.vote_record;

    // Update proposal vote count
    proposal.community_votes = proposal.community_votes
        .checked_add(vote_amount)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    msg!("Vote of {} tokens cast for proposal {}", vote_amount, proposal_id);

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct WithdrawVote<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,

    #[account(
        mut,
        seeds = [seeds::VOTE_RECORD, proposal_id.to_le_bytes().as_ref(), voter.key().as_ref()],
        bump = vote_record.bump,
        has_one = voter @ GovernanceError::Unauthorized,
    )]
    pub vote_record: Account<'info, VoteRecord>,

    /// Voter's AMOS token account
    #[account(
        mut,
        token::mint = governance_config.amos_mint,
        token::authority = voter,
    )]
    pub voter_token_account: Account<'info, anchor_spl::token::TokenAccount>,

    /// Escrow account for locked votes
    #[account(
        mut,
        seeds = [seeds::TREASURY],
        bump,
        token::mint = governance_config.amos_mint,
    )]
    pub vote_escrow: Account<'info, anchor_spl::token::TokenAccount>,

    #[account(mut)]
    pub voter: Signer<'info>,

    pub token_program: Program<'info, anchor_spl::token::Token>,
}

pub fn withdraw_vote(
    ctx: Context<WithdrawVote>,
    _proposal_id: u64,
) -> Result<()> {
    let vote_record = &mut ctx.accounts.vote_record;
    require!(!vote_record.withdrawn, GovernanceError::VoteAlreadyWithdrawn);

    let proposal = &mut ctx.accounts.proposal;
    
    // Can only withdraw if proposal is not yet in A/B testing
    require!(
        proposal.status == ProposalStatus::Submitted || 
        proposal.status == ProposalStatus::InDevelopment ||
        proposal.status == ProposalStatus::Rejected ||
        proposal.status == ProposalStatus::Cancelled,
        GovernanceError::InvalidProposalStatus
    );

    let vote_amount = vote_record.vote_amount;

    // Transfer tokens back from escrow
    let governance_key = ctx.accounts.governance_config.key();
    let seeds = &[seeds::GOVERNANCE_CONFIG, &[ctx.accounts.governance_config.bump]];
    let signer_seeds = &[&seeds[..]];

    anchor_spl::token::transfer(
        CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            anchor_spl::token::Transfer {
                from: ctx.accounts.vote_escrow.to_account_info(),
                to: ctx.accounts.voter_token_account.to_account_info(),
                authority: ctx.accounts.governance_config.to_account_info(),
            },
            signer_seeds,
        ),
        vote_amount,
    )?;

    // Update records
    vote_record.withdrawn = true;
    proposal.community_votes = proposal.community_votes
        .checked_sub(vote_amount)
        .ok_or(GovernanceError::ArithmeticOverflow)?;

    msg!("Vote of {} tokens withdrawn from proposal", vote_amount);

    Ok(())
}

#[derive(Accounts)]
#[instruction(proposal_id: u64)]
pub struct UpdateProposalStatus<'info> {
    #[account(
        seeds = [seeds::GOVERNANCE_CONFIG],
        bump = governance_config.bump,
        has_one = oracle_authority @ GovernanceError::UnauthorizedOracle,
    )]
    pub governance_config: Account<'info, GovernanceConfig>,

    #[account(
        mut,
        seeds = [seeds::FEATURE_PROPOSAL, proposal_id.to_le_bytes().as_ref()],
        bump = proposal.bump,
    )]
    pub proposal: Account<'info, FeatureProposal>,

    pub oracle_authority: Signer<'info>,
}

pub fn update_proposal_status(
    ctx: Context<UpdateProposalStatus>,
    _proposal_id: u64,
    new_status: ProposalStatus,
) -> Result<()> {
    let proposal = &mut ctx.accounts.proposal;
    let clock = Clock::get()?;

    // Track timestamps for certain status changes
    match new_status {
        ProposalStatus::InDevelopment => {
            proposal.development_started_at = Some(clock.unix_timestamp);
        }
        ProposalStatus::Merged => {
            proposal.completed_at = Some(clock.unix_timestamp);
        }
        _ => {}
    }

    proposal.status = new_status;

    msg!("Proposal status updated to {:?}", new_status);

    Ok(())
}
