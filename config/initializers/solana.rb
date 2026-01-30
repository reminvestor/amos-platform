# frozen_string_literal: true

# Solana Configuration for AMOS Token
#
# Configuration sources (in priority order):
# 1. Environment variables (SOLANA_*)
# 2. config/solana_token.yml
# 3. Defaults
#
# Environment Variables:
# - SOLANA_RPC_URL: RPC endpoint (mainnet/devnet)
# - SOLANA_TREASURY_ADDRESS: Treasury wallet public key
# - SOLANA_TREASURY_PRIVATE_KEY: Treasury wallet private key (encrypted in production)
# - SOLANA_TOKEN_MINT: SPL token mint address
# - SOLANA_NETWORK: 'mainnet' or 'devnet' (for UI display)

# Load YAML config if available
yaml_config = {}
yaml_path = Rails.root.join('config', 'solana_token.yml')
if File.exist?(yaml_path)
  all_config = YAML.load_file(yaml_path, permitted_classes: [Symbol])
  network = ENV.fetch('SOLANA_NETWORK', 'devnet')
  yaml_config = all_config[network] || {}
end

Rails.application.config.solana = {
  # Network configuration
  rpc_url: ENV.fetch('SOLANA_RPC_URL', yaml_config['network_url'] || 'https://api.devnet.solana.com'),
  network: ENV.fetch('SOLANA_NETWORK', 'devnet'),
  
  # Treasury wallet (holds tokens for distribution)
  treasury_address: ENV.fetch('SOLANA_TREASURY_ADDRESS', yaml_config['treasury_address']),
  treasury_token_account: yaml_config['treasury_token_account'],
  
  # Token mint address
  token_mint: ENV.fetch('SOLANA_TOKEN_MINT', yaml_config['token_mint']),
  
  # Token metadata
  token_name: 'Amos Platform Token',
  token_symbol: 'AMOS',
  token_decimals: 9,
  total_supply: 100_000_000,  # 100M tokens
  
  # Fee configuration
  claim_fee_rate: 0.01,  # 1% platform fee on claims
  minimum_claim: 100,    # Minimum tokens to claim
  
  # Explorer URLs
  explorer_url: ENV.fetch('SOLANA_EXPLORER_URL', 'https://explorer.solana.com'),
  
  # Feature flags
  claims_enabled: ENV.fetch('SOLANA_CLAIMS_ENABLED', 'false') == 'true',
  deposits_enabled: ENV.fetch('SOLANA_DEPOSITS_ENABLED', 'false') == 'true'
}

# Validate configuration in production
if Rails.env.production?
  config = Rails.application.config.solana
  
  if config[:claims_enabled] || config[:deposits_enabled]
    missing = []
    missing << 'SOLANA_TREASURY_ADDRESS' unless config[:treasury_address].present?
    missing << 'SOLANA_TOKEN_MINT' unless config[:token_mint].present?
    
    if missing.any?
      Rails.logger.warn "[SOLANA] Missing configuration: #{missing.join(', ')}"
      Rails.logger.warn "[SOLANA] Token claims/deposits are DISABLED"
      
      Rails.application.config.solana[:claims_enabled] = false
      Rails.application.config.solana[:deposits_enabled] = false
    end
  end
end

# Log configuration on startup
Rails.application.config.after_initialize do
  config = Rails.application.config.solana
  
  Rails.logger.info "[SOLANA] Configuration:"
  Rails.logger.info "[SOLANA]   Network: #{config[:network]}"
  Rails.logger.info "[SOLANA]   RPC URL: #{config[:rpc_url]}"
  Rails.logger.info "[SOLANA]   Token Mint: #{config[:token_mint] || 'NOT SET'}"
  Rails.logger.info "[SOLANA]   Treasury: #{config[:treasury_address] || 'NOT SET'}"
  Rails.logger.info "[SOLANA]   Claims Enabled: #{config[:claims_enabled]}"
  Rails.logger.info "[SOLANA]   Deposits Enabled: #{config[:deposits_enabled]}"
end
