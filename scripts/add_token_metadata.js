/**
 * Add metadata to AMOS token using Metaplex Umi
 */

const { createUmi } = require('@metaplex-foundation/umi-bundle-defaults');
const { createMetadataAccountV3, mplTokenMetadata } = require('@metaplex-foundation/mpl-token-metadata');
const { publicKey, signerIdentity, createSignerFromKeypair } = require('@metaplex-foundation/umi');
const fs = require('fs');
const path = require('path');

// Configuration
const NETWORK = 'https://api.devnet.solana.com';
const TOKEN_MINT = '4M4fQTVvuCJ9uJcBhMfmjzqgx2RbJCDZqzupo9Pgp2cT';

// Token Metadata
const TOKEN_NAME = 'Amos Platform Token';
const TOKEN_SYMBOL = 'AMOS';
const TOKEN_URI = ''; // JSON metadata URI

async function main() {
  console.log('Adding metadata to AMOS token...\n');
  
  // Create Umi instance
  const umi = createUmi(NETWORK).use(mplTokenMetadata());
  
  // Load mint authority keypair
  const mintAuthorityPath = path.join(process.env.HOME, 'amos-mint-authority.json');
  const secretKey = JSON.parse(fs.readFileSync(mintAuthorityPath, 'utf-8'));
  
  const keypair = umi.eddsa.createKeypairFromSecretKey(new Uint8Array(secretKey));
  const signer = createSignerFromKeypair(umi, keypair);
  
  umi.use(signerIdentity(signer));
  
  console.log('Mint Authority:', signer.publicKey);
  
  const mint = publicKey(TOKEN_MINT);
  
  console.log('Creating metadata...');
  
  try {
    const result = await createMetadataAccountV3(umi, {
      mint: mint,
      mintAuthority: signer,
      payer: signer,
      updateAuthority: signer.publicKey,
      data: {
        name: TOKEN_NAME,
        symbol: TOKEN_SYMBOL,
        uri: TOKEN_URI,
        sellerFeeBasisPoints: 0,
        creators: null,
        collection: null,
        uses: null,
      },
      isMutable: true,
      collectionDetails: null,
    }).sendAndConfirm(umi);
    
    console.log('\n✅ Metadata added successfully!');
    console.log('Signature:', result.signature);
    console.log('\nToken Name:', TOKEN_NAME);
    console.log('Token Symbol:', TOKEN_SYMBOL);
    console.log('\nView on explorer (may take a moment to update):');
    console.log(`https://explorer.solana.com/address/${TOKEN_MINT}?cluster=devnet`);
    
  } catch (err) {
    console.error('\n❌ Error:', err.message);
    
    // Check if it's because mint authority is disabled
    if (err.message.includes('mint authority') || err.message.includes('Mint authority mismatch')) {
      console.log('\n⚠️  Note: The mint authority for this token has been disabled.');
      console.log('For tokens with disabled mint authority, metadata must be added BEFORE disabling.');
      console.log('\nWorkaround: You can register the token on Jupiter/Raydium with custom metadata.');
    }
  }
}

main().catch(console.error);
