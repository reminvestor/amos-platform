#!/bin/bash

# =============================================================================
# AMOS Token Setup Script for Solana
# =============================================================================
# This script creates the AMOS token on Solana (devnet or mainnet)
#
# Prerequisites:
# - Solana CLI installed (solana --version)
# - spl-token CLI installed
# - Founder wallet already created at ~/amos-founder.json
#
# Usage:
#   ./scripts/setup_solana_token.sh devnet    # For testing
#   ./scripts/setup_solana_token.sh mainnet   # For production (CAREFUL!)
# =============================================================================

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NETWORK="${1:-devnet}"
TOTAL_SUPPLY=100000000  # 100 million tokens
DECIMALS=9

# Wallet paths
FOUNDER_WALLET="$HOME/amos-founder.json"
TREASURY_WALLET="$HOME/amos-treasury.json"
MINT_AUTHORITY_WALLET="$HOME/amos-mint-authority.json"

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}  AMOS Token Setup - Solana ${NETWORK}${NC}"
echo -e "${BLUE}=============================================${NC}"
echo ""

# Validate network
if [[ "$NETWORK" != "devnet" && "$NETWORK" != "mainnet-beta" && "$NETWORK" != "mainnet" ]]; then
    echo -e "${RED}Invalid network. Use 'devnet' or 'mainnet'${NC}"
    exit 1
fi

# Convert mainnet shorthand
if [[ "$NETWORK" == "mainnet" ]]; then
    NETWORK="mainnet-beta"
fi

# Safety check for mainnet
if [[ "$NETWORK" == "mainnet-beta" ]]; then
    echo -e "${RED}⚠️  WARNING: You are about to create a REAL token on MAINNET!${NC}"
    echo -e "${YELLOW}This action is IRREVERSIBLE and will cost real SOL.${NC}"
    read -p "Type 'I UNDERSTAND' to continue: " confirmation
    if [[ "$confirmation" != "I UNDERSTAND" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Set Solana config to the right network
echo -e "${BLUE}Setting network to ${NETWORK}...${NC}"
solana config set --url "$NETWORK"

# Check if founder wallet exists
if [[ ! -f "$FOUNDER_WALLET" ]]; then
    echo -e "${RED}Founder wallet not found at $FOUNDER_WALLET${NC}"
    echo "Please create it first with: solana-keygen new --outfile $FOUNDER_WALLET"
    exit 1
fi

FOUNDER_ADDRESS=$(solana address -k "$FOUNDER_WALLET")
echo -e "${GREEN}✓ Founder wallet: $FOUNDER_ADDRESS${NC}"

# Step 1: Create Treasury Wallet
echo ""
echo -e "${BLUE}Step 1: Creating Treasury Wallet...${NC}"
if [[ -f "$TREASURY_WALLET" ]]; then
    echo -e "${YELLOW}Treasury wallet already exists${NC}"
    TREASURY_ADDRESS=$(solana address -k "$TREASURY_WALLET")
else
    solana-keygen new --outfile "$TREASURY_WALLET" --no-bip39-passphrase --force
    TREASURY_ADDRESS=$(solana address -k "$TREASURY_WALLET")
fi
echo -e "${GREEN}✓ Treasury wallet: $TREASURY_ADDRESS${NC}"

# Step 2: Create Mint Authority Wallet (temporary - will be disabled)
echo ""
echo -e "${BLUE}Step 2: Creating Mint Authority Wallet...${NC}"
if [[ -f "$MINT_AUTHORITY_WALLET" ]]; then
    echo -e "${YELLOW}Mint authority wallet already exists${NC}"
    MINT_AUTH_ADDRESS=$(solana address -k "$MINT_AUTHORITY_WALLET")
else
    solana-keygen new --outfile "$MINT_AUTHORITY_WALLET" --no-bip39-passphrase --force
    MINT_AUTH_ADDRESS=$(solana address -k "$MINT_AUTHORITY_WALLET")
fi
echo -e "${GREEN}✓ Mint authority: $MINT_AUTH_ADDRESS${NC}"

# Step 3: Airdrop SOL for fees (devnet only)
if [[ "$NETWORK" == "devnet" ]]; then
    echo ""
    echo -e "${BLUE}Step 3: Airdropping SOL for transaction fees...${NC}"
    
    # Airdrop to founder
    echo "Airdropping to founder..."
    solana airdrop 2 "$FOUNDER_ADDRESS" --url devnet || true
    sleep 2
    
    # Airdrop to treasury
    echo "Airdropping to treasury..."
    solana airdrop 2 "$TREASURY_ADDRESS" --url devnet || true
    sleep 2
    
    # Airdrop to mint authority
    echo "Airdropping to mint authority..."
    solana airdrop 2 "$MINT_AUTH_ADDRESS" --url devnet || true
    sleep 2
    
    echo -e "${GREEN}✓ Airdrops completed${NC}"
else
    echo ""
    echo -e "${YELLOW}Step 3: Skipping airdrop (mainnet)${NC}"
    echo "Make sure all wallets have sufficient SOL for fees!"
fi

# Check balances
echo ""
echo -e "${BLUE}Checking balances...${NC}"
FOUNDER_BALANCE=$(solana balance "$FOUNDER_ADDRESS" | awk '{print $1}')
TREASURY_BALANCE=$(solana balance "$TREASURY_ADDRESS" | awk '{print $1}')
MINT_AUTH_BALANCE=$(solana balance "$MINT_AUTH_ADDRESS" | awk '{print $1}')

echo "  Founder:        $FOUNDER_BALANCE SOL"
echo "  Treasury:       $TREASURY_BALANCE SOL"
echo "  Mint Authority: $MINT_AUTH_BALANCE SOL"

# Step 4: Create the Token Mint
echo ""
echo -e "${BLUE}Step 4: Creating AMOS Token Mint...${NC}"
echo "This will create a new SPL token with $DECIMALS decimals"

# Use mint authority wallet to create the token
TOKEN_MINT=$(spl-token create-token \
    --decimals $DECIMALS \
    --mint-authority "$MINT_AUTHORITY_WALLET" \
    --fee-payer "$MINT_AUTHORITY_WALLET" \
    2>&1 | grep "Creating token" | awk '{print $3}')

if [[ -z "$TOKEN_MINT" ]]; then
    # Try alternative parsing
    TOKEN_MINT=$(spl-token create-token \
        --decimals $DECIMALS \
        --mint-authority "$MINT_AUTHORITY_WALLET" \
        --fee-payer "$MINT_AUTHORITY_WALLET" \
        2>&1 | tail -1)
fi

echo -e "${GREEN}✓ Token Mint Created: $TOKEN_MINT${NC}"

# Step 5: Create Token Account for Treasury
echo ""
echo -e "${BLUE}Step 5: Creating Treasury Token Account...${NC}"

TREASURY_TOKEN_ACCOUNT=$(spl-token create-account "$TOKEN_MINT" \
    --owner "$TREASURY_WALLET" \
    --fee-payer "$MINT_AUTHORITY_WALLET" \
    2>&1 | grep "Creating account" | awk '{print $3}')

if [[ -z "$TREASURY_TOKEN_ACCOUNT" ]]; then
    TREASURY_TOKEN_ACCOUNT=$(spl-token create-account "$TOKEN_MINT" \
        --owner "$TREASURY_WALLET" \
        --fee-payer "$MINT_AUTHORITY_WALLET" \
        2>&1 | tail -1)
fi

echo -e "${GREEN}✓ Treasury Token Account: $TREASURY_TOKEN_ACCOUNT${NC}"

# Step 6: Mint Total Supply to Treasury
echo ""
echo -e "${BLUE}Step 6: Minting $TOTAL_SUPPLY AMOS tokens to Treasury...${NC}"

spl-token mint "$TOKEN_MINT" $TOTAL_SUPPLY "$TREASURY_TOKEN_ACCOUNT" \
    --mint-authority "$MINT_AUTHORITY_WALLET" \
    --fee-payer "$MINT_AUTHORITY_WALLET"

echo -e "${GREEN}✓ Minted $TOTAL_SUPPLY tokens to treasury${NC}"

# Step 7: Disable Mint Authority (IMMUTABLE!)
echo ""
echo -e "${RED}Step 7: DISABLING MINT AUTHORITY (IRREVERSIBLE!)${NC}"
echo -e "${YELLOW}This will prevent any future token minting.${NC}"

if [[ "$NETWORK" == "mainnet-beta" ]]; then
    read -p "Type 'DISABLE FOREVER' to continue: " disable_confirm
    if [[ "$disable_confirm" != "DISABLE FOREVER" ]]; then
        echo "Mint authority NOT disabled. You can do this later."
    else
        spl-token authorize "$TOKEN_MINT" mint --disable \
            --authority "$MINT_AUTHORITY_WALLET" \
            --fee-payer "$MINT_AUTHORITY_WALLET"
        echo -e "${GREEN}✓ Mint authority DISABLED - No more tokens can ever be created${NC}"
    fi
else
    # Auto-disable on devnet
    spl-token authorize "$TOKEN_MINT" mint --disable \
        --authority "$MINT_AUTHORITY_WALLET" \
        --fee-payer "$MINT_AUTHORITY_WALLET"
    echo -e "${GREEN}✓ Mint authority DISABLED${NC}"
fi

# Step 8: Verify Setup
echo ""
echo -e "${BLUE}Step 8: Verifying Setup...${NC}"

echo ""
echo "Token Supply:"
spl-token supply "$TOKEN_MINT"

echo ""
echo "Treasury Balance:"
spl-token balance "$TOKEN_MINT" --owner "$TREASURY_WALLET"

# Summary
echo ""
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}  AMOS Token Setup Complete!${NC}"
echo -e "${GREEN}=============================================${NC}"
echo ""
echo -e "Network:          ${BLUE}$NETWORK${NC}"
echo -e "Token Mint:       ${BLUE}$TOKEN_MINT${NC}"
echo -e "Total Supply:     ${BLUE}$TOTAL_SUPPLY AMOS${NC}"
echo -e "Decimals:         ${BLUE}$DECIMALS${NC}"
echo ""
echo -e "Wallets:"
echo -e "  Founder:        ${BLUE}$FOUNDER_ADDRESS${NC}"
echo -e "  Treasury:       ${BLUE}$TREASURY_ADDRESS${NC}"
echo ""
echo -e "${YELLOW}IMPORTANT: Save these addresses!${NC}"
echo ""

# Save config for the Rails app
CONFIG_FILE="config/solana_token.yml"
echo ""
echo -e "${BLUE}Saving configuration to $CONFIG_FILE...${NC}"

cat > "$CONFIG_FILE" << EOF
# AMOS Token Configuration - Generated $(date)
# DO NOT COMMIT THIS FILE WITH REAL MAINNET VALUES

$NETWORK:
  token_mint: "$TOKEN_MINT"
  treasury_address: "$TREASURY_ADDRESS"
  founder_address: "$FOUNDER_ADDRESS"
  decimals: $DECIMALS
  total_supply: $TOTAL_SUPPLY
  network_url: "https://api.$NETWORK.solana.com"
EOF

echo -e "${GREEN}✓ Configuration saved to $CONFIG_FILE${NC}"

# Update .gitignore
if ! grep -q "config/solana_token.yml" .gitignore 2>/dev/null; then
    echo "config/solana_token.yml" >> .gitignore
    echo -e "${GREEN}✓ Added config/solana_token.yml to .gitignore${NC}"
fi

echo ""
echo -e "${GREEN}Setup complete! 🚀${NC}"
echo ""
echo "Next steps:"
echo "1. View your token on Solana Explorer:"
echo "   https://explorer.solana.com/address/$TOKEN_MINT?cluster=$NETWORK"
echo ""
echo "2. Update your Rails app configuration with the token mint address"
echo ""
echo "3. For mainnet launch, seed liquidity on Jupiter/Raydium"
