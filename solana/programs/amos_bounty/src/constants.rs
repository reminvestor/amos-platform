// ═══════════════════════════════════════════════════════════════════════════════
// AMOS BOUNTY ECONOMICS CONSTANTS
//
// CRITICAL: These values are IMMUTABLE once the program is deployed.
// They encode the trustless rules of the bounty → token pipeline.
//
// Changes to these constants require deploying a completely new program
// (with a new address), which means all participants must opt-in to migrate.
// This IS the trust guarantee.
// ═══════════════════════════════════════════════════════════════════════════════

/// ═══════════════════════════════════════════════════════════════════════════
/// TOKEN SUPPLY & EMISSION
/// ═══════════════════════════════════════════════════════════════════════════

/// Total AMOS supply ever (in smallest unit, 6 decimals)
/// 100,000,000 AMOS = 100_000_000_000_000 lamports
pub const TOTAL_SUPPLY: u64 = 100_000_000;

/// Treasury allocation for contributor rewards: 60% of supply
/// This is the pool that daily emissions draw from
pub const TREASURY_ALLOCATION: u64 = 60_000_000;

/// Initial daily emission pool (AMOS tokens per day)
/// This decreases via halving schedule
pub const INITIAL_DAILY_EMISSION: u64 = 16_000;

/// ═══════════════════════════════════════════════════════════════════════════
/// HALVING SCHEDULE
/// ═══════════════════════════════════════════════════════════════════════════
/// Emission halves every HALVING_INTERVAL_DAYS days.
/// Year 1: 16,000/day → Year 2: 8,000/day → Year 3: 4,000/day → ...
/// This creates scarcity and rewards early contributors.

/// Days between halving events
pub const HALVING_INTERVAL_DAYS: u64 = 365;

/// Minimum daily emission (floor — never goes below this)
/// Ensures there's always some reward for contributors
pub const MINIMUM_DAILY_EMISSION: u64 = 100;

/// Maximum halving epochs (prevents underflow)
pub const MAX_HALVING_EPOCHS: u64 = 10;

/// ═══════════════════════════════════════════════════════════════════════════
/// DECAY PARAMETERS
/// ═══════════════════════════════════════════════════════════════════════════
/// Inactive stakes decay over time to prevent "stake and forget" hoarding.
/// Decay is DYNAMIC based on platform health metrics.

/// Minimum annual decay rate (basis points) — during healthy growth
pub const MIN_DECAY_RATE_BPS: u64 = 200; // 2%

/// Maximum annual decay rate (basis points) — during stagnation
pub const MAX_DECAY_RATE_BPS: u64 = 2500; // 25%

/// Default annual decay rate (basis points)
pub const DEFAULT_DECAY_RATE_BPS: u64 = 500; // 5%

/// Days of inactivity before decay begins
/// Users who interact with the platform regularly don't decay
pub const DECAY_GRACE_PERIOD_DAYS: u64 = 90;

/// Decay floor: minimum percentage of original stake that's preserved
/// Prevents total wipeout of long-term holders
pub const DECAY_FLOOR_BPS: u64 = 1000; // 10% minimum preserved

/// Portion of decayed tokens that are burned (rest recycled to treasury)
pub const DECAY_BURN_PORTION_BPS: u64 = 1000; // 10% burned, 90% recycled

/// ═══════════════════════════════════════════════════════════════════════════
/// BOUNTY PROOF REQUIREMENTS
/// ═══════════════════════════════════════════════════════════════════════════
/// The platform submits "proofs of work" to the chain.
/// The chain verifies the proof and distributes tokens.

/// Minimum quality score for bounty approval (0-100)
pub const MIN_QUALITY_SCORE: u8 = 30;

/// Maximum points per single bounty (prevents gaming)
pub const MAX_BOUNTY_POINTS: u64 = 2000;

/// Maximum bounties per operator per day (on-chain enforcement)
pub const MAX_DAILY_BOUNTIES_PER_OPERATOR: u64 = 50;

/// ═══════════════════════════════════════════════════════════════════════════
/// EXTERNAL AGENT TRUST LEVELS (on-chain enforcement)
/// ═══════════════════════════════════════════════════════════════════════════
/// Trust level thresholds are encoded on-chain so they can't be
/// silently changed by the platform operator.

/// Trust level 1 → 2: minimum completions and reputation
pub const TRUST_2_MIN_COMPLETIONS: u64 = 3;
pub const TRUST_2_MIN_REPUTATION_BPS: u64 = 5500; // 55%

/// Trust level 2 → 3
pub const TRUST_3_MIN_COMPLETIONS: u64 = 10;
pub const TRUST_3_MIN_REPUTATION_BPS: u64 = 6500; // 65%

/// Trust level 3 → 4
pub const TRUST_4_MIN_COMPLETIONS: u64 = 25;
pub const TRUST_4_MIN_REPUTATION_BPS: u64 = 7500; // 75%

/// Trust level 4 → 5 (Elite)
pub const TRUST_5_MIN_COMPLETIONS: u64 = 50;
pub const TRUST_5_MIN_REPUTATION_BPS: u64 = 8500; // 85%

/// Maximum trust level
pub const MAX_TRUST_LEVEL: u8 = 5;

/// Maximum points per trust level (on-chain cap)
pub const TRUST_LEVEL_MAX_POINTS: [u64; 5] = [100, 200, 500, 1000, 2000];

/// Daily bounty limits per trust level
pub const TRUST_LEVEL_DAILY_LIMITS: [u64; 5] = [3, 5, 10, 15, 25];

/// ═══════════════════════════════════════════════════════════════════════════
/// CONTRIBUTION MULTIPLIERS
/// ═══════════════════════════════════════════════════════════════════════════
/// Different contribution types earn different base point multipliers.
/// These ensure code contributions are valued alongside community work.

/// Multiplier for feature development (basis points of bounty points)
pub const MULTIPLIER_FEATURE_BPS: u64 = 10000; // 100% (baseline)

/// Multiplier for bug fixes
pub const MULTIPLIER_BUG_FIX_BPS: u64 = 12000; // 120% (bonus for fixing)

/// Multiplier for documentation
pub const MULTIPLIER_DOCS_BPS: u64 = 8000; // 80%

/// Multiplier for content/marketing
pub const MULTIPLIER_CONTENT_BPS: u64 = 9000; // 90%

/// Multiplier for support
pub const MULTIPLIER_SUPPORT_BPS: u64 = 7000; // 70%

/// Multiplier for testing/QA
pub const MULTIPLIER_TESTING_BPS: u64 = 11000; // 110% (bonus for quality)

/// Multiplier for design
pub const MULTIPLIER_DESIGN_BPS: u64 = 10000; // 100%

/// Multiplier for infrastructure
pub const MULTIPLIER_INFRA_BPS: u64 = 13000; // 130% (highest — core platform)

/// ═══════════════════════════════════════════════════════════════════════════
/// REVIEW REWARDS
/// ═══════════════════════════════════════════════════════════════════════════
/// Human reviewers earn a percentage of the bounty they review.
/// This incentivizes quality verification.

/// Reviewer reward as percentage of bounty points
pub const REVIEWER_REWARD_BPS: u64 = 500; // 5% of bounty goes to reviewer

/// ═══════════════════════════════════════════════════════════════════════════
/// BASIS POINTS & PDA SEEDS
/// ═══════════════════════════════════════════════════════════════════════════

pub const BPS_DENOMINATOR: u64 = 10000;

pub mod seeds {
    pub const BOUNTY_CONFIG: &[u8] = b"bounty_config";
    pub const EMISSION_POOL: &[u8] = b"emission_pool";
    pub const BOUNTY_PROOF: &[u8] = b"bounty_proof";
    pub const OPERATOR_STATS: &[u8] = b"operator_stats";
    pub const AGENT_TRUST: &[u8] = b"agent_trust";
    pub const DAILY_POOL: &[u8] = b"daily_pool";
    pub const DECAY_CONFIG: &[u8] = b"decay_config";
}

/// ═══════════════════════════════════════════════════════════════════════════
/// VERIFICATION TESTS
/// ═══════════════════════════════════════════════════════════════════════════

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn treasury_allocation_is_60_percent() {
        assert_eq!(
            TREASURY_ALLOCATION,
            TOTAL_SUPPLY * 60 / 100,
            "Treasury must be 60% of supply"
        );
    }

    #[test]
    fn decay_range_is_valid() {
        assert!(MIN_DECAY_RATE_BPS < MAX_DECAY_RATE_BPS);
        assert!(DEFAULT_DECAY_RATE_BPS >= MIN_DECAY_RATE_BPS);
        assert!(DEFAULT_DECAY_RATE_BPS <= MAX_DECAY_RATE_BPS);
    }

    #[test]
    fn trust_levels_are_progressive() {
        assert!(TRUST_2_MIN_COMPLETIONS < TRUST_3_MIN_COMPLETIONS);
        assert!(TRUST_3_MIN_COMPLETIONS < TRUST_4_MIN_COMPLETIONS);
        assert!(TRUST_4_MIN_COMPLETIONS < TRUST_5_MIN_COMPLETIONS);
        assert!(TRUST_2_MIN_REPUTATION_BPS < TRUST_3_MIN_REPUTATION_BPS);
        assert!(TRUST_3_MIN_REPUTATION_BPS < TRUST_4_MIN_REPUTATION_BPS);
        assert!(TRUST_4_MIN_REPUTATION_BPS < TRUST_5_MIN_REPUTATION_BPS);
    }

    #[test]
    fn trust_level_points_are_progressive() {
        for i in 1..TRUST_LEVEL_MAX_POINTS.len() {
            assert!(TRUST_LEVEL_MAX_POINTS[i] > TRUST_LEVEL_MAX_POINTS[i - 1]);
        }
    }

    #[test]
    fn trust_level_daily_limits_are_progressive() {
        for i in 1..TRUST_LEVEL_DAILY_LIMITS.len() {
            assert!(TRUST_LEVEL_DAILY_LIMITS[i] > TRUST_LEVEL_DAILY_LIMITS[i - 1]);
        }
    }

    #[test]
    fn decay_floor_is_reasonable() {
        assert!(DECAY_FLOOR_BPS > 0, "Decay floor must preserve something");
        assert!(DECAY_FLOOR_BPS <= 5000, "Decay floor can't preserve more than 50%");
    }

    #[test]
    fn minimum_emission_is_positive() {
        assert!(MINIMUM_DAILY_EMISSION > 0, "Must always have some emission");
    }

    #[test]
    fn reviewer_reward_is_reasonable() {
        assert!(REVIEWER_REWARD_BPS > 0, "Reviewers must earn something");
        assert!(REVIEWER_REWARD_BPS <= 2000, "Reviewer reward can't exceed 20%");
    }
}
