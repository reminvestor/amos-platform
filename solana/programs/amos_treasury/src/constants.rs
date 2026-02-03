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
pub const HOLDER_SHARE_BPS: u64 = 5000;

/// R&D share: 30% of all revenue
/// This goes to a multi-sig wallet, spent via governance votes
pub const RND_SHARE_BPS: u64 = 3000;

/// Operations share: 10% of all revenue
/// This goes to a multi-sig wallet for day-to-day expenses
pub const OPS_SHARE_BPS: u64 = 1000;

/// Reserve share: 10% of all revenue
/// This goes to a PDA (program-controlled), accessible only via DAO vote
pub const RESERVE_SHARE_BPS: u64 = 1000;

/// ═══════════════════════════════════════════════════════════════════════════
/// AMOS TOKEN PAYMENT SPLIT (When paying directly in AMOS)
/// ═══════════════════════════════════════════════════════════════════════════

/// AMOS burn percentage: 50% of AMOS payments are burned
/// This creates deflationary pressure and rewards all holders
pub const AMOS_BURN_BPS: u64 = 5000;

/// AMOS holder share: 25% of AMOS payments go to holder pool
pub const AMOS_HOLDER_BPS: u64 = 2500;

/// AMOS operations share: 25% of AMOS payments go to operations
pub const AMOS_OPS_BPS: u64 = 2500;

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
            AMOS_BURN_BPS + AMOS_HOLDER_BPS + AMOS_OPS_BPS,
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
}
