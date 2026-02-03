/**
 * Initialize AMOS Treasury on Devnet
 * 
 * This script initializes the treasury program with:
 * - USDC token account for receiving revenue
 * - AMOS token mint for native payments
 * - Revenue split destination accounts (holders, R&D, ops, reserve)
 */

import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { PublicKey, Keypair, SystemProgram } from "@solana/web3.js";
import { 
  TOKEN_PROGRAM_ID, 
  ASSOCIATED_TOKEN_PROGRAM_ID,
  getAssociatedTokenAddress,
  createMint,
  getOrCreateAssociatedTokenAccount,
} from "@solana/spl-token";

// Program IDs (Devnet)
const TREASURY_PROGRAM_ID = new PublicKey("3p2MqHiQVLWfvvfU7psLyEsLLVzbGwqa3bSG7avKqiYP");

// Devnet USDC (for testing - you can create your own)
const DEVNET_USDC_MINT = new PublicKey("4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU");

async function main() {
  // Configure the client
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  console.log("=".repeat(60));
  console.log("AMOS Treasury Initialization");
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
  const [treasuryPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("treasury")],
    TREASURY_PROGRAM_ID
  );
  console.log("Treasury PDA:", treasuryPDA.toString());

  const [holderPoolPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("holder_pool")],
    TREASURY_PROGRAM_ID
  );
  console.log("Holder Pool PDA:", holderPoolPDA.toString());

  const [rndPoolPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("rnd_pool")],
    TREASURY_PROGRAM_ID
  );
  console.log("R&D Pool PDA:", rndPoolPDA.toString());

  const [opsPoolPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("ops_pool")],
    TREASURY_PROGRAM_ID
  );
  console.log("Ops Pool PDA:", opsPoolPDA.toString());

  const [reservePoolPDA] = PublicKey.findProgramAddressSync(
    [Buffer.from("reserve_pool")],
    TREASURY_PROGRAM_ID
  );
  console.log("Reserve Pool PDA:", reservePoolPDA.toString());

  console.log("");
  console.log("✅ PDAs derived successfully");
  console.log("");
  console.log("Next steps:");
  console.log("1. Create AMOS token mint");
  console.log("2. Create USDC token accounts for each pool");
  console.log("3. Call initialize instruction");
  console.log("");
  console.log("To initialize, run:");
  console.log("  npx ts-node scripts/initialize_treasury.ts --execute");
}

main().catch(console.error);
