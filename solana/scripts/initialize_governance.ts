/**
 * Initialize AMOS Governance on Devnet
 * 
 * This script initializes the governance program with:
 * - Governance config account
 * - Initial parameters (voting periods, quorum, etc.)
 * - Oracle authority for gate results
 */

import * as anchor from "@coral-xyz/anchor";
import { PublicKey, Keypair, SystemProgram } from "@solana/web3.js";

// Program IDs (Devnet)
const GOVERNANCE_PROGRAM_ID = new PublicKey("AQEf6P1qhKC2dCTMhqRh2rmKNpcQsR4ahwT1MvSoSehu");
const TREASURY_PROGRAM_ID = new PublicKey("3p2MqHiQVLWfvvfU7psLyEsLLVzbGwqa3bSG7avKqiYP");

// Default governance parameters
const DEFAULT_PARAMS = {
  // Priority calculation weights (basis points)
  mrrWeightBps: 3000,        // 30% weight for MRR impact
  communityWeightBps: 2000,  // 20% weight for community votes
  recencyHalfLifeDays: 30,   // Recency decay half-life
  
  // Quality gates
  minBenchmarkScore: 70,     // Min score to pass benchmark (0-100)
  minAbImprovementBps: 500,  // 5% min improvement in A/B test
  minFeedbackRatioBps: 7500, // 75% positive feedback required
  stewardQuorum: 5,          // 5-of-7 stewards must approve
  
  // Bounty rewards (basis points of total bounty)
  bountyCompletionBps: 4000, // 40% on completion
  bountyAbSuccessBps: 3000,  // 30% on A/B success
  bountyStableMergeBps: 3000,// 30% on stable merge
  
  // Research funding
  maxResearchStipend: 10000, // Max 10,000 AMOS for research
  researchMilestonesRequired: 3, // 3 milestones required
  researchSuccessMultiplierBps: 8000, // 80% bonus on success
};

async function main() {
  // Configure the client
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  console.log("=".repeat(60));
  console.log("AMOS Governance Initialization");
  console.log("=".repeat(60));
  console.log("Wallet:", provider.wallet.publicKey.toString());
  console.log("Cluster:", provider.connection.rpcEndpoint);
  console.log("");

  // Check balance
  const balance = await provider.connection.getBalance(provider.wallet.publicKey);
  console.log("Balance:", balance / 1e9, "SOL");

  if (balance < 0.1 * 1e9) {
    console.error("❌ Insufficient balance. Need at least 0.1 SOL");
    process.exit(1);
  }

  // Derive PDAs
  const [governanceConfigPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("governance_config")],
    GOVERNANCE_PROGRAM_ID
  );
  console.log("Governance Config PDA:", governanceConfigPDA.toString());

  const [treasuryPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("treasury")],
    TREASURY_PROGRAM_ID
  );
  console.log("Treasury PDA:", treasuryPDA.toString());

  console.log("");
  console.log("Default Parameters:");
  console.log("-------------------");
  Object.entries(DEFAULT_PARAMS).forEach(([key, value]) => {
    console.log(`  ${key}: ${value}`);
  });

  console.log("");
  console.log("✅ PDAs derived successfully");
  console.log("");
  console.log("Next steps:");
  console.log("1. Ensure Treasury is initialized first");
  console.log("2. Create AMOS token mint");
  console.log("3. Call initialize_governance instruction");
  console.log("");
  console.log("To initialize, run:");
  console.log("  npx ts-node scripts/initialize_governance.ts --execute");
}

main().catch(console.error);
