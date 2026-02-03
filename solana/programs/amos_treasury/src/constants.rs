// ═══════════════════════════════════════════════════════════════════════════════
// AMOS TREASURY CONSTANTS
// 
// CRITICAL: These values are IMMUTABLE once the program is deployed.
// They are compiled into the program binary and cannot be changed
// without deploying a completely new program (with a new address).
// 
// This is the core TRUST GUARANTEE of the AMOS token economy.
// ═══════════════════════════════════════════════════════════════════════════════

/// ═══════════════════════════════════════════════════════════════════════════
/// REVENUE SPLIT PERCENTAGES (USDC Payments)
/// ═══════════════════════════════════════════════════════════════════════════

/// Token holder share: 50% of all revenue
/// This goes to the holder pool, claimable proportionally by stakers
/// THE core value proposition - immutable and trustless
pub const HOLDER_SHARE_BPS: u64 = 5000;

/// R&D share: 40% of all revenue
/// This goes to a multi-sig wallet (R&D Council), spent via governance votes
/// Covers: software development, infrastructure, research grants, AI self-work
pub const RND_SHARE_BPS: u64 = 4000;

/// Operations share: 5% of all revenue
/// This goes to a multi-sig wallet for required USD expenses only
/// Covers: accounting, legal, minimal hosting/SaaS
pub const OPS_SHARE_BPS: u64 = 500;

/// Treasury/Reserve share: 5% of all revenue
/// Emergency fund - accessible only via DAO supermajority vote
/// Covers: black swan events, refund buffer, acquisition defense
pub const RESERVE_SHARE_BPS: u64 = 500;

/// ═══════════════════════════════════════════════════════════════════════════
/// AMOS TOKEN PAYMENT SPLIT (When paying directly in AMOS)
/// ═══════════════════════════════════════════════════════════════════════════

/// AMOS burn percentage: 50% of AMOS payments are burned
/// This creates deflationary pressure and rewards ALL holders (staked or not)
/// The burn benefits everyone by reducing supply
pub const AMOS_BURN_BPS: u64 = 5000;

/// AMOS holder share: 50% of AMOS payments go to holder pool
/// Stakers can claim this proportionally
/// Note: R&D/Ops need USDC, so AMOS payments don't fund them directly
pub const AMOS_HOLDER_BPS: u64 = 5000;

/// ═══════════════════════════════════════════════════════════════════════════
/// ELIGIBILITY REQUIREMENTS
/// ═══════════════════════════════════════════════════════════════════════════

/// Minimum days a stake must be held before earning revenue share
/// This prevents "just-in-time" staking attacks
pub const MIN_STAKE_DAYS: u64 = 30;

/// Minimum stake amount to be eligible for revenue share
/// Prevents dust accounts from clogging the system
pub const MIN_STAKE_AMOUNT: u64 = 100;

/// ═══════════════════════════════════════════════════════════════════════════
/// AMOS LABS ENTITY LOCKUP (10-Year Commitment)
/// ═══════════════════════════════════════════════════════════════════════════
/// 
/// The AMOS Labs entity pool is subject to a 10-year lockup with NO decay.
/// This signals long-term commitment and eliminates dump risk.
/// The company can only profit through revenue share, not token sales.
/// ═══════════════════════════════════════════════════════════════════════════

/// AMOS Labs entity allocation: 15% of total supply
/// 15,000,000 AMOS locked in smart contract
pub const ENTITY_ALLOCATION: u64 = 15_000_000;

/// Entity lockup duration: 10 years (in seconds)
/// Tokens cannot be transferred or sold during this period
pub const ENTITY_LOCKUP_SECONDS: i64 = 10 * 365 * 24 * 60 * 60; // 315,360,000

/// Entity unlock schedule: 2 years linear unlock after lockup ends
/// 12.5% unlocked every quarter (8 tranches)
pub const ENTITY_UNLOCK_SECONDS: i64 = 2 * 365 * 24 * 60 * 60; // 63,072,000

/// Number of unlock tranches after lockup
pub const ENTITY_UNLOCK_TRANCHES: u64 = 8;

/// Entity lockup decay exemption
/// Locked tokens do NOT decay (0% annual decay)
pub const ENTITY_LOCKUP_DECAY_BPS: u64 = 0;

/// Entity CAN stake for revenue share despite lockup
/// This is the ONLY way AMOS Labs earns from the tokens
pub const ENTITY_CAN_STAKE: bool = true;

/// Entity CAN vote in governance despite lockup
/// Skin in the game = voting rights
pub const ENTITY_CAN_VOTE: bool = true;

/// ═══════════════════════════════════════════════════════════════════════════
/// LP INCENTIVE PROGRAM
/// ═══════════════════════════════════════════════════════════════════════════
/// 
/// Liquidity providers earn from trading fees (via AMM) plus AMOS incentives.
/// Incentives are vested to prevent farm-and-dump attacks.
/// Early LPs get multipliers to reward bootstrapping.
/// ═══════════════════════════════════════════════════════════════════════════

/// Total AMOS allocated to LP incentives (3% of supply)
pub const LP_INCENTIVE_ALLOCATION: u64 = 3_000_000;

/// Year 1 LP incentive distribution
pub const LP_INCENTIVE_YEAR_1: u64 = 1_500_000;

/// Year 2 LP incentive distribution
pub const LP_INCENTIVE_YEAR_2: u64 = 1_000_000;

/// Year 3 LP incentive distribution
pub const LP_INCENTIVE_YEAR_3: u64 = 500_000;

/// LP reward vesting period (30 days in seconds)
/// LPs must stay for full period to claim all rewards
pub const LP_VESTING_SECONDS: i64 = 30 * 24 * 60 * 60; // 2,592,000

/// Early withdrawal penalty (forfeited rewards go back to pool)
/// Day 1-7: 100% forfeit, Day 8-14: 75%, Day 15-21: 50%, Day 22-30: 25%
pub const LP_EARLY_WITHDRAW_PENALTY_BPS: [u64; 4] = [10000, 7500, 5000, 2500];

/// ═══════════════════════════════════════════════════════════════════════════
/// FOUNDER LP PERMANENT FEE
/// ═══════════════════════════════════════════════════════════════════════════
/// 
/// The first LP (Founder LP) receives a permanent fee share as reward for
/// bootstrapping the market. This fee is ADDITIONAL to normal LP fees.
/// ═══════════════════════════════════════════════════════════════════════════

/// Founder LP permanent fee share (0.05% of all trades forever)
/// This is separate from the 0.25% AMM fee that goes to all LPs
pub const FOUNDER_LP_FEE_BPS: u64 = 5; // 0.05%

/// Founder LP threshold - first LP up to this amount gets Founder status
pub const FOUNDER_LP_THRESHOLD: u64 = 10_000; // $10,000 USD equivalent

/// Founder LP is permanent - cannot be revoked even if LP withdrawn
pub const FOUNDER_LP_PERMANENT: bool = true;

/// ═══════════════════════════════════════════════════════════════════════════
/// TIME-WEIGHTED LP MULTIPLIERS
/// ═══════════════════════════════════════════════════════════════════════════
/// 
/// Early LPs get bonus multipliers on their incentive rewards.
/// Rewards long-term commitment and early risk-taking.
/// ═══════════════════════════════════════════════════════════════════════════

/// Week 1 LP multiplier (2x rewards)
pub const LP_WEEK_1_MULTIPLIER: u64 = 200; // 2.0x in basis points / 100

/// Week 2-4 LP multiplier (1.5x rewards)
pub const LP_WEEK_2_4_MULTIPLIER: u64 = 150; // 1.5x

/// Month 2+ LP multiplier (1x rewards - baseline)
pub const LP_BASELINE_MULTIPLIER: u64 = 100; // 1.0x

/// ═══════════════════════════════════════════════════════════════════════════
/// LP LOCKUP BONUSES
/// ═══════════════════════════════════════════════════════════════════════════

/// 30-day LP lock bonus
pub const LP_LOCK_30_DAY_BONUS_BPS: u64 = 2000; // +20%

/// 90-day LP lock bonus  
pub const LP_LOCK_90_DAY_BONUS_BPS: u64 = 5000; // +50%

/// 1-year LP lock bonus
pub const LP_LOCK_1_YEAR_BONUS_BPS: u64 = 10000; // +100%

/// ═══════════════════════════════════════════════════════════════════════════
/// PAYMENT DISCOUNTS
/// ═══════════════════════════════════════════════════════════════════════════

/// Discount for paying in USDC directly (basis points)
/// Users who pay in USDC skip Stripe fees
pub const USDC_DISCOUNT_BPS: u64 = 500; // 5%

/// Discount for paying in AMOS tokens (basis points)
/// Users who pay in AMOS get the largest discount (and create burn)
pub const AMOS_DISCOUNT_BPS: u64 = 1500; // 15%

/// ═══════════════════════════════════════════════════════════════════════════
/// BASIS POINTS MATH
/// ═══════════════════════════════════════════════════════════════════════════

/// Basis points denominator (100% = 10000 bps)
pub const BPS_DENOMINATOR: u64 = 10000;

/// ═══════════════════════════════════════════════════════════════════════════
/// PDA SEEDS
/// ═══════════════════════════════════════════════════════════════════════════

pub mod seeds {
    /// Treasury configuration account
    pub const TREASURY_CONFIG: &[u8] = b"treasury_config";
    
    /// Holder pool account (where claimable USDC accumulates)
    pub const HOLDER_POOL: &[u8] = b"holder_pool";
    
    /// Reserve account (DAO-controlled emergency fund)
    pub const RESERVE: &[u8] = b"reserve";
    
    /// Individual stake registration
    pub const STAKE_RECORD: &[u8] = b"stake";
    
    /// Distribution history
    pub const DISTRIBUTION: &[u8] = b"distribution";
}

/// ═══════════════════════════════════════════════════════════════════════════
/// VERIFICATION: The splits add up to 100%
/// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn usdc_splits_add_to_100_percent() {
        assert_eq!(
            HOLDER_SHARE_BPS + RND_SHARE_BPS + OPS_SHARE_BPS + RESERVE_SHARE_BPS,
            BPS_DENOMINATOR,
            "USDC splits must add to 100%"
        );
    }

    #[test]
    fn amos_splits_add_to_100_percent() {
        assert_eq!(
            AMOS_BURN_BPS + AMOS_HOLDER_BPS,
            BPS_DENOMINATOR,
            "AMOS splits must add to 100%"
        );
    }

    #[test]
    fn holder_share_is_50_percent() {
        assert_eq!(HOLDER_SHARE_BPS, 5000, "Holder share must be 50%");
    }

    #[test]
    fn amos_burn_is_50_percent() {
        assert_eq!(AMOS_BURN_BPS, 5000, "AMOS burn must be 50%");
    }

    #[test]
    fn lp_incentives_add_up() {
        assert_eq!(
            LP_INCENTIVE_YEAR_1 + LP_INCENTIVE_YEAR_2 + LP_INCENTIVE_YEAR_3,
            LP_INCENTIVE_ALLOCATION,
            "LP incentives must equal total allocation"
        );
    }

    #[test]
    fn entity_lockup_is_10_years() {
        let ten_years_seconds = 10 * 365 * 24 * 60 * 60;
        assert_eq!(ENTITY_LOCKUP_SECONDS, ten_years_seconds, "Entity lockup must be 10 years");
    }

    #[test]
    fn founder_lp_fee_is_point_05_percent() {
        assert_eq!(FOUNDER_LP_FEE_BPS, 5, "Founder LP fee must be 0.05%");
    }
}
