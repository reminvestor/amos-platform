use anchor_lang::prelude::*;

pub mod constants;
pub mod errors;
pub mod instructions;
pub mod state;

use instructions::*;

declare_id!("AmosTreas111111111111111111111111111111111");

/// AMOS Treasury Program
/// 
/// This on-chain program manages the TRUSTLESS revenue distribution:
/// - Receives USDC from payment processors
/// - Immediately splits according to IMMUTABLE percentages
/// - Token holders claim their share without approval
/// - Multi-sig wallets receive R&D and Operations funds
/// 
/// CRITICAL: The split percentages are CONSTANTS in this code.
/// Once deployed, they CANNOT be changed without deploying
/// a completely new program (which would have a different address).
#[program]
pub mod amos_treasury {
    use super::*;

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// Initialize the treasury configuration
    /// Called once at program deployment
    pub fn initialize(
        ctx: Context<Initialize>,
        rnd_multisig: Pubkey,
        ops_multisig: Pubkey,
    ) -> Result<()> {
        instructions::admin::initialize(ctx, rnd_multisig, ops_multisig)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REVENUE RECEIPT (Called by payment webhook)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Receive USDC revenue and immediately split
    /// This is the core function - atomic, trustless distribution
    pub fn receive_revenue(
        ctx: Context<ReceiveRevenue>,
        amount: u64,
        payment_reference: String,
    ) -> Result<()> {
        instructions::revenue::receive_revenue(ctx, amount, payment_reference)
    }

    /// Receive AMOS token payment (with burn mechanism)
    /// 50% burned, 25% to holders, 25% to operations
    pub fn receive_amos_payment(
        ctx: Context<ReceiveAmosPayment>,
        amount: u64,
        payment_reference: String,
    ) -> Result<()> {
        instructions::revenue::receive_amos_payment(ctx, amount, payment_reference)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HOLDER CLAIMS (Anyone can call for themselves)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Register stake for revenue eligibility
    /// Must hold for MIN_STAKE_DAYS before claiming
    pub fn register_stake(
        ctx: Context<RegisterStake>,
        amount: u64,
    ) -> Result<()> {
        instructions::claims::register_stake(ctx, amount)
    }

    /// Update stake amount (sync from platform)
    pub fn update_stake(
        ctx: Context<UpdateStake>,
        new_amount: u64,
    ) -> Result<()> {
        instructions::claims::update_stake(ctx, new_amount)
    }

    /// Claim accumulated revenue share
    /// No approval needed - proportional to stake
    pub fn claim_revenue(ctx: Context<ClaimRevenue>) -> Result<()> {
        instructions::claims::claim_revenue(ctx)
    }

    /// View claimable amount (read-only helper)
    pub fn get_claimable_amount(ctx: Context<GetClaimable>) -> Result<u64> {
        instructions::claims::get_claimable_amount(ctx)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRANSPARENCY (Read-only queries)
    // ═══════════════════════════════════════════════════════════════════════════

    /// Get current treasury state (for dashboard)
    pub fn get_treasury_state(ctx: Context<GetTreasuryState>) -> Result<TreasuryStats> {
        instructions::transparency::get_treasury_state(ctx)
    }

    /// Get distribution history
    pub fn get_distribution_history(
        ctx: Context<GetDistributionHistory>,
        limit: u8,
    ) -> Result<Vec<DistributionRecord>> {
        instructions::transparency::get_distribution_history(ctx, limit)
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// SHARED TYPES
// ═══════════════════════════════════════════════════════════════════════════

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct TreasuryStats {
    pub total_revenue_received: u64,
    pub total_distributed_to_holders: u64,
    pub total_distributed_to_rnd: u64,
    pub total_distributed_to_ops: u64,
    pub total_to_reserve: u64,
    pub total_amos_burned: u64,
    pub holder_pool_balance: u64,
    pub eligible_stake: u64,
    pub distribution_count: u64,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone)]
pub struct DistributionRecord {
    pub timestamp: i64,
    pub amount: u64,
    pub payment_reference: String,
    pub holder_share: u64,
    pub rnd_share: u64,
    pub ops_share: u64,
    pub reserve_share: u64,
}
