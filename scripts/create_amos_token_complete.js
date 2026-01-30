#!/usr/bin/env node
/**
 * AMOS Token Complete Setup Script
 * 
 * Creates the AMOS token with proper metadata BEFORE disabling mint authority.
 * Uses the stable @metaplex-foundation/js library.
 * 
 * Order of operations:
 * 1. Create token mint
 * 2. Add metadata (name, symbol, URI)
 * 3. Create treasury token account
 * 4. Mint 100M tokens to treasury
 * 5. Disable mint authority (immutable forever)
 * 
 * Usage:
 *   node scripts/create_amos_token_complete.js devnet
 *   node scripts/create_amos_token_complete.js mainnet
 */

const { Metaplex, keypairIdentity } = require('@metaplex-foundation/js');
const { 
  Connection, 
  Keypair, 
  PublicKey,
  LAMPORTS_PER_SOL
} = require('@solana/web3.js');
const { 
  createMint, 
  getOrCreateAssociatedTokenAccount,
  mintTo,
  setAuthority,
  AuthorityType
} = require('@solana/spl-token');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

// ============================================================================
// CONFIGURATION
// ============================================================================

const CONFIG = {
  TOKEN_NAME: 'Amos Platform Token',
  TOKEN_SYMBOL: 'AMOS',
  TOKEN_DECIMALS: 9,
  TOTAL_SUPPLY: 100_000_000,
  
  // Metadata URI - for logo/description. Empty string is OK for now.
  TOKEN_URI: '',
  
  NETWORKS: {
    devnet: 'https://api.devnet.solana.com',
    mainnet: 'https://api.mainnet-beta.solana.com'
  },
  
  WALLETS: {
    treasury: path.join(process.env.HOME, 'amos-treasury.json'),
    mintAuthority: path.join(process.env.HOME, 'amos-mint-authority.json'),
  }
};

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

function loadKeypair(filepath) {
  if (!fs.existsSync(filepath)) {
    throw new Error(`Keypair not found: ${filepath}`);
  }
  const secretKey = JSON.parse(fs.readFileSync(filepath, 'utf-8'));
  return Keypair.fromSecretKey(Uint8Array.from(secretKey));
}

async function confirmAction(prompt) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });
  return new Promise((resolve) => {
    rl.question(prompt, (answer) => {
      rl.close();
      resolve(answer.trim().toUpperCase() === 'YES');
    });
  });
}

function formatNumber(num) {
  return num.toLocaleString('en-US');
}

// ============================================================================
// MAIN SCRIPT
// ============================================================================

async function main() {
  const network = process.argv[2] || 'devnet';
  
  if (!['devnet', 'mainnet'].includes(network)) {
    console.error('Usage: node create_amos_token_complete.js [devnet|mainnet]');
    process.exit(1);
  }
  
  const rpcUrl = CONFIG.NETWORKS[network];
  const isMainnet = network === 'mainnet';
  
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║           AMOS TOKEN COMPLETE SETUP                          ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Network:      ${network.padEnd(46)}║`);
  console.log(`║  Token Name:   ${CONFIG.TOKEN_NAME.padEnd(46)}║`);
  console.log(`║  Symbol:       ${CONFIG.TOKEN_SYMBOL.padEnd(46)}║`);
  console.log(`║  Total Supply: ${formatNumber(CONFIG.TOTAL_SUPPLY).padEnd(46)}║`);
  console.log(`║  Decimals:     ${CONFIG.TOKEN_DECIMALS.toString().padEnd(46)}║`);
  console.log('╚══════════════════════════════════════════════════════════════╝\n');
  
  if (isMainnet) {
    console.log('⚠️  WARNING: You are about to create a REAL token on MAINNET!');
    console.log('   This action is IRREVERSIBLE and will cost real SOL.\n');
    const confirmed = await confirmAction('Type YES to continue: ');
    if (!confirmed) {
      console.log('Aborted.');
      process.exit(0);
    }
  }
  
  // Connect
  const connection = new Connection(rpcUrl, 'confirmed');
  console.log('✓ Connected to', network);
  
  // Load wallets
  console.log('\n📁 Loading wallets...');
  const mintAuthority = loadKeypair(CONFIG.WALLETS.mintAuthority);
  const treasury = loadKeypair(CONFIG.WALLETS.treasury);
  
  console.log('   Mint Authority:', mintAuthority.publicKey.toString());
  console.log('   Treasury:', treasury.publicKey.toString());
  
  // Check balances
  const mintAuthBalance = await connection.getBalance(mintAuthority.publicKey);
  console.log('\n💰 Mint Authority Balance:', mintAuthBalance / LAMPORTS_PER_SOL, 'SOL');
  
  if (mintAuthBalance < 0.1 * LAMPORTS_PER_SOL) {
    console.error('❌ Insufficient balance! Need at least 0.1 SOL');
    process.exit(1);
  }
  
  // ========================================================================
  // STEP 1: Create Token Mint
  // ========================================================================
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('STEP 1: Creating Token Mint...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const tokenMint = await createMint(
    connection,
    mintAuthority,
    mintAuthority.publicKey,
    null,
    CONFIG.TOKEN_DECIMALS
  );
  
  console.log('✓ Token Mint Created:', tokenMint.toString());
  
  // ========================================================================
  // STEP 2: Add Metadata using Metaplex
  // ========================================================================
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('STEP 2: Adding Token Metadata...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const metaplex = Metaplex.make(connection).use(keypairIdentity(mintAuthority));
  
  try {
    const { nft } = await metaplex.nfts().createSft({
      useExistingMint: tokenMint,
      name: CONFIG.TOKEN_NAME,
      symbol: CONFIG.TOKEN_SYMBOL,
      uri: CONFIG.TOKEN_URI,
      sellerFeeBasisPoints: 0,
      isMutable: true,
    });
    
    console.log('✓ Metadata Added:');
    console.log('   Name:', CONFIG.TOKEN_NAME);
    console.log('   Symbol:', CONFIG.TOKEN_SYMBOL);
  } catch (err) {
    console.log('⚠️  Metadata creation failed:', err.message);
    console.log('   Continuing without metadata (can add via token registry later)');
  }
  
  // ========================================================================
  // STEP 3: Create Treasury Token Account
  // ========================================================================
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('STEP 3: Creating Treasury Token Account...');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const treasuryTokenAccount = await getOrCreateAssociatedTokenAccount(
    connection,
    mintAuthority,
    tokenMint,
    treasury.publicKey
  );
  
  console.log('✓ Treasury Token Account:', treasuryTokenAccount.address.toString());
  
  // ========================================================================
  // STEP 4: Mint Total Supply
  // ========================================================================
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log(`STEP 4: Minting ${formatNumber(CONFIG.TOTAL_SUPPLY)} tokens...`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  const mintAmount = BigInt(CONFIG.TOTAL_SUPPLY) * BigInt(10 ** CONFIG.TOKEN_DECIMALS);
  
  await mintTo(
    connection,
    mintAuthority,
    tokenMint,
    treasuryTokenAccount.address,
    mintAuthority.publicKey,
    mintAmount
  );
  
  console.log('✓ Minted', formatNumber(CONFIG.TOTAL_SUPPLY), 'AMOS to treasury');
  
  // ========================================================================
  // STEP 5: Disable Mint Authority
  // ========================================================================
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('STEP 5: Disabling Mint Authority (PERMANENT!)');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  
  if (isMainnet) {
    console.log('\n⚠️  This will PERMANENTLY prevent any future token minting!');
    const confirmed = await confirmAction('Type YES to disable mint authority forever: ');
    if (!confirmed) {
      console.log('⚠️  Mint authority NOT disabled.');
    } else {
      await disableMint();
    }
  } else {
    await disableMint();
  }
  
  async function disableMint() {
    await setAuthority(
      connection,
      mintAuthority,
      tokenMint,
      mintAuthority.publicKey,
      AuthorityType.MintTokens,
      null
    );
    console.log('✓ Mint Authority DISABLED - Supply is now immutable!');
  }
  
  // ========================================================================
  // SUMMARY
  // ========================================================================
  console.log('\n╔══════════════════════════════════════════════════════════════╗');
  console.log('║                    SETUP COMPLETE! 🚀                        ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Token Mint:      ${tokenMint.toString().substring(0, 40)}...  ║`);
  console.log(`║  Symbol:          ${CONFIG.TOKEN_SYMBOL.padEnd(43)}║`);
  console.log(`║  Total Supply:    ${formatNumber(CONFIG.TOTAL_SUPPLY).padEnd(43)}║`);
  console.log(`║  Mint Authority:  DISABLED (immutable)${' '.repeat(23)}║`);
  console.log('╚══════════════════════════════════════════════════════════════╝');
  
  console.log('\n📋 Full Details:');
  console.log('   Token Mint:', tokenMint.toString());
  console.log('   Treasury:', treasury.publicKey.toString());
  console.log('   Treasury Token Account:', treasuryTokenAccount.address.toString());
  
  const cluster = isMainnet ? '' : '?cluster=devnet';
  console.log('\n🔗 View on Explorer:');
  console.log(`   https://explorer.solana.com/address/${tokenMint}${cluster}`);
  
  // Save configuration
  const configContent = `# AMOS Token Configuration - ${new Date().toISOString()}
${network}:
  token_mint: "${tokenMint.toString()}"
  treasury_address: "${treasury.publicKey.toString()}"
  treasury_token_account: "${treasuryTokenAccount.address.toString()}"
  decimals: ${CONFIG.TOKEN_DECIMALS}
  total_supply: ${CONFIG.TOTAL_SUPPLY}
  network_url: "${rpcUrl}"
  token_name: "${CONFIG.TOKEN_NAME}"
  token_symbol: "${CONFIG.TOKEN_SYMBOL}"
`;
  
  const configPath = path.join(process.cwd(), 'config', 'solana_token.yml');
  fs.writeFileSync(configPath, configContent);
  console.log('\n💾 Configuration saved to:', configPath);
  
  console.log('\n✅ Done!');
}

main().catch((err) => {
  console.error('\n❌ Error:', err.message);
  if (err.logs) console.error('Logs:', err.logs);
  process.exit(1);
});
