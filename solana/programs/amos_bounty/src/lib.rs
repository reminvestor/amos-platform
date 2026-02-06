use anchor_lang::prelude::*;

pub mod constants;
pub mod errors;
pub mod instructions;
pub mod state;

use instructions::*;

declare_id!("AmosBnty111111111111111111111111111111111111");

/// AMOS Bounty Program
///
/// This on-chain program manages the TRUSTLESS bounty economics:
///
/// 1. EMISSION: Daily token pool from treasury (with halving)
/// 2. DISTRIBUTION: Platform submits proofs → chain distributes tokens
/// 3. DECAY: Inactive stakes decay (within immutable bounds)
/// 4. TRUST: External agent trust levels enforced on-chain
///
/// The platform is the WITNESS (submits proofs of completed work).
/// The blockchain is the JUDGE (enforces rules, distributes tokens).
///
/// WHAT THE PLATFORM CAN DO:
/// - Submit bounty completion proofs
/// - Request trust level upgrades (chain verifies thresholds)
/// - Update decay rate (within 2-25% bounds)
/// - Advance halving epoch (when time has passed)
///
/// WHAT THE PLATFORM CANNOT DO:
/// - Mint tokens beyond the 100M supply
/// - Change the distribution formula
/// - Bypass trust level thresholds
/// - Set decay rate outside 2-25% range
/// - Award tokens without a valid bounty proof
/// - Skip reviewer rewards
#[program]
pub mod amos_bounty {
    use super::*;

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Initialize the bounty program (called once at deployment)
    pub fn initialize(
        ctx: Context<Initialize>,
        oracle_authority: Pubkey,
    ) -> Result<()> {
        instructions::admin::initialize(ctx, oracle_authority)
    }

    /// Update decay rate (oracle only, within 2-25% bounds)
    pub fn update_decay_rate(
        ctx: Context<UpdateDecayRate>,
        new_rate_bps: u64,
    ) -> Result<()> {
        instructions::admin::update_decay_rate(ctx, new_rate_bps)
    }

    /// Advance halving epoch (anyone can call when time has passed)
    pub fn advance_halving(ctx: Context<AdvanceHalving>) -> Result<()> {
        instructions::admin::advance_halving(ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // BOUNTY DISTRIBUTION (platform oracle submits proofs)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Submit a bounty completion proof and distribute tokens
    ///
    /// tokens = (points × multiplier / total_points_today) × daily_emission
    ///
    /// This is THE core function. The oracle proves work happened,
    /// the chain enforces the immutable formula.
    pub fn submit_bounty_proof(
        ctx: Context<SubmitBountyProof>,
        bounty_id: u64,
        operator: Pubkey,
        points: u64,
        quality_score: u8,
        bounty_type: u8,
        is_external_agent: bool,
        agent_id: u64,
        agent_trust_level: u8,
        reviewer: Pubkey,
        evidence_hash: [u8; 32],
        proof_reference: String,
    ) -> Result<()> {
        instructions::distribution::submit_bounty_proof(
            ctx, bounty_id, operator, points, quality_score,
            bounty_type, is_external_agent, agent_id, agent_trust_level,
            reviewer, evidence_hash, proof_reference,
        )
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // DECAY (anyone can trigger for any operator)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Apply decay to inactive operator stake
    /// 90-day grace period, 2-25% annual rate, 10% floor preserved
    pub fn apply_decay(ctx: Context<ApplyDecay>) -> Result<()> {
        instructions::decay::apply_decay(ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXTERNAL AGENT TRUST (on-chain enforcement)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Register an external agent's trust record
    pub fn register_agent_trust(
        ctx: Context<RegisterAgentTrust>,
        agent_id: u64,
        operator: Pubkey,
    ) -> Result<()> {
        instructions::trust::register_agent_trust(ctx, agent_id, operator)
    }

    /// Record a bounty completion (updates agent stats for trust progression)
    pub fn record_agent_completion(
        ctx: Context<RecordAgentCompletion>,
        agent_id: u64,
        approved: bool,
        tokens_earned: u64,
    ) -> Result<()> {
        instructions::trust::record_agent_completion(ctx, agent_id, approved, tokens_earned)
    }

    /// Upgrade agent trust level (chain verifies thresholds)
    pub fn upgrade_trust_level(
        ctx: Context<UpgradeTrustLevel>,
        agent_id: u64,
    ) -> Result<()> {
        instructions::trust::upgrade_trust_level(ctx, agent_id)
    }
}
