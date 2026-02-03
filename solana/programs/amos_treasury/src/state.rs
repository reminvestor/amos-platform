use anchor_lang::prelude::*;

/// Treasury configuration account
/// Stores multisig addresses and running totals
#[account]
#[derive(Default)]
pub struct TreasuryConfig {
    /// Program authority (for initialization only)
    pub authority: Pubkey,
    
    /// R&D multisig wallet address
    pub rnd_multisig: Pubkey,
    
    /// Operations multisig wallet address
    pub ops_multisig: Pubkey,
    
    /// USDC token mint address
    pub usdc_mint: Pubkey,
    
    /// AMOS token mint address
    pub amos_mint: Pubkey,
    
    /// Total USDC revenue ever received
    pub total_revenue_received: u64,
    
    /// Total distributed to holder pool
    pub total_to_holders: u64,
    
    /// Total distributed to R&D
    pub total_to_rnd: u64,
    
    /// Total distributed to operations
    pub total_to_ops: u64,
    
    /// Total sent to reserve
    pub total_to_reserve: u64,
    
    /// Total AMOS tokens burned
    pub total_amos_burned: u64,
    
    /// Number of distributions processed
    pub distribution_count: u64,
    
    /// Total eligible stake (for share calculation)
    pub total_eligible_stake: u64,
    
    /// Timestamp of last distribution
    pub last_distribution_at: i64,
    
    /// Bump seed for PDA
    pub bump: u8,
}

impl TreasuryConfig {
    pub const SIZE: usize = 8 + // discriminator
        32 + // authority
        32 + // rnd_multisig
        32 + // ops_multisig
        32 + // usdc_mint
        32 + // amos_mint
        8 +  // total_revenue_received
        8 +  // total_to_holders
        8 +  // total_to_rnd
        8 +  // total_to_ops
        8 +  // total_to_reserve
        8 +  // total_amos_burned
        8 +  // distribution_count
        8 +  // total_eligible_stake
        8 +  // last_distribution_at
        1;   // bump
}

/// Individual stake record for revenue eligibility
#[account]
#[derive(Default)]
pub struct StakeRecord {
    /// Owner of this stake
    pub owner: Pubkey,
    
    /// Current stake amount (synced from platform)
    pub amount: u64,
    
    /// When the stake was first registered
    pub registered_at: i64,
    
    /// Last time the stake was updated
    pub updated_at: i64,
    
    /// Total USDC claimed by this staker
    pub total_claimed: u64,
    
    /// Last claim timestamp
    pub last_claim_at: i64,
    
    /// Accumulated unclaimed revenue
    pub unclaimed_revenue: u64,
    
    /// Bump seed for PDA
    pub bump: u8,
}

impl StakeRecord {
    pub const SIZE: usize = 8 + // discriminator
        32 + // owner
        8 +  // amount
        8 +  // registered_at
        8 +  // updated_at
        8 +  // total_claimed
        8 +  // last_claim_at
        8 +  // unclaimed_revenue
        1;   // bump
}

/// Distribution record for transparency
#[account]
#[derive(Default)]
pub struct Distribution {
    /// Distribution index (sequential)
    pub index: u64,
    
    /// Timestamp of distribution
    pub timestamp: i64,
    
    /// Total amount received
    pub total_amount: u64,
    
    /// Amount to holder pool
    pub holder_amount: u64,
    
    /// Amount to R&D
    pub rnd_amount: u64,
    
    /// Amount to operations
    pub ops_amount: u64,
    
    /// Amount to reserve
    pub reserve_amount: u64,
    
    /// AMOS burned (if AMOS payment)
    pub amos_burned: u64,
    
    /// Payment reference (from webhook)
    pub payment_reference: String,
    
    /// Payment type: 0 = USDC, 1 = AMOS
    pub payment_type: u8,
    
    /// Bump seed for PDA
    pub bump: u8,
}

impl Distribution {
    pub const SIZE: usize = 8 + // discriminator
        8 +  // index
        8 +  // timestamp
        8 +  // total_amount
        8 +  // holder_amount
        8 +  // rnd_amount
        8 +  // ops_amount
        8 +  // reserve_amount
        8 +  // amos_burned
        4 + 64 + // payment_reference (String with max 64 chars)
        1 +  // payment_type
        1;   // bump
}

/// Holder pool account (token account for claimable USDC)
#[account]
#[derive(Default)]
pub struct HolderPool {
    /// Current USDC balance available for claims
    pub balance: u64,
    
    /// Total ever deposited
    pub total_deposited: u64,
    
    /// Total ever claimed
    pub total_claimed: u64,
    
    /// Number of claims processed
    pub claim_count: u64,
    
    /// Bump seed for PDA
    pub bump: u8,
}

impl HolderPool {
    pub const SIZE: usize = 8 + // discriminator
        8 +  // balance
        8 +  // total_deposited
        8 +  // total_claimed
        8 +  // claim_count
        1;   // bump
}
