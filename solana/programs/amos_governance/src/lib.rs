use anchor_lang::prelude::*;

pub mod state;
pub mod instructions;
pub mod errors;
pub mod constants;

use instructions::*;

declare_id!("AmosGov111111111111111111111111111111111111");

/// Amos Governance Program
/// 
/// This on-chain program manages:
/// - Feature proposal lifecycle and voting
/// - Research proposal funding and graduation
/// - Priority scoring algorithm (MRR-weighted)
/// - Quality gate thresholds and results
/// - Staged reward calculations and claims
/// - Parameter governance for algorithm updates
#[program]
pub mod amos_governance {
    use super::*;

    // ============================================
    // GOVERNANCE CONFIG INSTRUCTIONS
    // ============================================

    /// Initialize the governance configuration
    /// Only called once by the platform authority
    pub fn initialize_governance(
        ctx: Context<InitializeGovernance>,
        config: GovernanceConfigParams,
    ) -> Result<()> {
        instructions::governance::initialize_governance(ctx, config)
    }

    /// Update governance parameters (requires steward council approval)
    pub fn update_governance_params(
        ctx: Context<UpdateGovernanceParams>,
        new_params: GovernanceConfigParams,
    ) -> Result<()> {
        instructions::governance::update_governance_params(ctx, new_params)
    }

    // ============================================
    // FEATURE PROPOSAL INSTRUCTIONS
    // ============================================

    /// Submit a new feature proposal
    pub fn submit_feature_proposal(
        ctx: Context<SubmitFeatureProposal>,
        title: String,
        description: String,
        estimated_bounty: u64,
        customer_request_ids: Vec<u64>,
    ) -> Result<()> {
        instructions::proposals::submit_feature_proposal(
            ctx, title, description, estimated_bounty, customer_request_ids
        )
    }

    /// Vote for a feature proposal (weighted by AMOS tokens)
    pub fn vote_for_feature(
        ctx: Context<VoteForFeature>,
        proposal_id: u64,
        vote_amount: u64,
    ) -> Result<()> {
        instructions::proposals::vote_for_feature(ctx, proposal_id, vote_amount)
    }

    /// Withdraw vote from a feature proposal
    pub fn withdraw_vote(
        ctx: Context<WithdrawVote>,
        proposal_id: u64,
    ) -> Result<()> {
        instructions::proposals::withdraw_vote(ctx, proposal_id)
    }

    /// Update feature proposal status (oracle authority only)
    pub fn update_proposal_status(
        ctx: Context<UpdateProposalStatus>,
        proposal_id: u64,
        new_status: ProposalStatus,
    ) -> Result<()> {
        instructions::proposals::update_proposal_status(ctx, proposal_id, new_status)
    }

    // ============================================
    // QUALITY GATE INSTRUCTIONS
    // ============================================

    /// Report benchmark result (oracle authority only)
    pub fn report_benchmark_result(
        ctx: Context<ReportBenchmarkResult>,
        proposal_id: u64,
        passed: bool,
        score: u16,
        evidence_hash: [u8; 32],
    ) -> Result<()> {
        instructions::gates::report_benchmark_result(ctx, proposal_id, passed, score, evidence_hash)
    }

    /// Report A/B test result (oracle authority only)
    pub fn report_ab_test_result(
        ctx: Context<ReportAbTestResult>,
        proposal_id: u64,
        passed: bool,
        improvement_bps: i16,  // basis points, can be negative
        sample_size: u32,
        confidence_bps: u16,
        evidence_hash: [u8; 32],
    ) -> Result<()> {
        instructions::gates::report_ab_test_result(
            ctx, proposal_id, passed, improvement_bps, sample_size, confidence_bps, evidence_hash
        )
    }

    /// Report customer feedback result (oracle authority only)
    pub fn report_feedback_result(
        ctx: Context<ReportFeedbackResult>,
        proposal_id: u64,
        passed: bool,
        positive_count: u32,
        negative_count: u32,
        evidence_hash: [u8; 32],
    ) -> Result<()> {
        instructions::gates::report_feedback_result(
            ctx, proposal_id, passed, positive_count, negative_count, evidence_hash
        )
    }

    /// Report steward council approval (oracle authority only)
    pub fn report_steward_approval(
        ctx: Context<ReportStewardApproval>,
        proposal_id: u64,
        approved: bool,
        approvals: u8,
        rejections: u8,
    ) -> Result<()> {
        instructions::gates::report_steward_approval(ctx, proposal_id, approved, approvals, rejections)
    }

    // ============================================
    // REWARD INSTRUCTIONS
    // ============================================

    /// Claim bounty reward for a completed gate
    pub fn claim_bounty_reward(
        ctx: Context<ClaimBountyReward>,
        proposal_id: u64,
        gate_type: GateType,
    ) -> Result<()> {
        instructions::rewards::claim_bounty_reward(ctx, proposal_id, gate_type)
    }

    /// Finalize rewards after full merge to main
    pub fn finalize_rewards(
        ctx: Context<FinalizeRewards>,
        proposal_id: u64,
    ) -> Result<()> {
        instructions::rewards::finalize_rewards(ctx, proposal_id)
    }

    // ============================================
    // RESEARCH PROPOSAL INSTRUCTIONS
    // ============================================

    /// Submit a research proposal
    pub fn submit_research_proposal(
        ctx: Context<SubmitResearchProposal>,
        title: String,
        description: String,
        requested_stipend: u64,
        milestone_count: u8,
    ) -> Result<()> {
        instructions::research::submit_research_proposal(
            ctx, title, description, requested_stipend, milestone_count
        )
    }

    /// Approve research proposal (steward council)
    pub fn approve_research(
        ctx: Context<ApproveResearch>,
        proposal_id: u64,
        approved_stipend: u64,
    ) -> Result<()> {
        instructions::research::approve_research(ctx, proposal_id, approved_stipend)
    }

    /// Report research milestone completion
    pub fn report_research_milestone(
        ctx: Context<ReportResearchMilestone>,
        proposal_id: u64,
        milestone_index: u8,
        evidence_hash: [u8; 32],
    ) -> Result<()> {
        instructions::research::report_research_milestone(ctx, proposal_id, milestone_index, evidence_hash)
    }

    /// Graduate research to feature proposal
    pub fn graduate_research(
        ctx: Context<GraduateResearch>,
        research_proposal_id: u64,
        feature_bounty: u64,
    ) -> Result<()> {
        instructions::research::graduate_research(ctx, research_proposal_id, feature_bounty)
    }

    // ============================================
    // PRIORITY CALCULATION (VIEW ONLY)
    // ============================================

    /// Calculate priority score for a proposal (view function)
    /// Priority = (MRR_weight * customer_votes) + (community_votes * community_weight) + recency_bonus
    pub fn calculate_priority(
        ctx: Context<CalculatePriority>,
        proposal_id: u64,
    ) -> Result<u64> {
        instructions::priority::calculate_priority(ctx, proposal_id)
    }
}

// ============================================
// SHARED TYPES
// ============================================

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq)]
pub enum ProposalStatus {
    Draft,
    Submitted,
    InDevelopment,
    InReview,
    InAbTest,
    AwaitingFeedback,
    AwaitingStewardApproval,
    Approved,
    Merged,
    Rejected,
    Cancelled,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq)]
pub enum GateType {
    Benchmark,
    AbTest,
    CustomerFeedback,
    StewardApproval,
    FinalMerge,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct GovernanceConfigParams {
    /// MRR weight in priority calculation (basis points)
    pub mrr_weight_bps: u16,
    /// Community vote weight (basis points)
    pub community_weight_bps: u16,
    /// Recency decay half-life in days
    pub recency_half_life_days: u16,
    /// Minimum benchmark score to pass (0-10000)
    pub min_benchmark_score: u16,
    /// Minimum A/B test improvement (basis points)
    pub min_ab_improvement_bps: i16,
    /// Minimum feedback approval ratio (basis points)
    pub min_feedback_ratio_bps: u16,
    /// Steward council quorum
    pub steward_quorum: u8,
    /// Bounty split: completion percentage (basis points)
    pub bounty_completion_bps: u16,
    /// Bounty split: A/B success percentage (basis points)  
    pub bounty_ab_success_bps: u16,
    /// Bounty split: stable merge percentage (basis points)
    pub bounty_stable_merge_bps: u16,
    /// Research stipend percentage (basis points of requested)
    pub research_stipend_bps: u16,
    /// Research success bonus multiplier (basis points)
    pub research_success_multiplier_bps: u16,
}
