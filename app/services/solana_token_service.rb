# frozen_string_literal: true

# SolanaTokenService handles all Solana blockchain operations for the AMOS token
#
# Responsibilities:
# - Send tokens from treasury to user wallets (claims)
# - Verify incoming deposits
# - Check balances
# - Monitor transaction status
#
# Configuration (ENV):
# - SOLANA_RPC_URL: Solana RPC endpoint (mainnet/devnet)
# - SOLANA_TREASURY_ADDRESS: Treasury wallet public key
# - SOLANA_TREASURY_PRIVATE_KEY: Treasury wallet private key (encrypted)
# - SOLANA_TOKEN_MINT: SPL token mint address
class SolanaTokenService
  class SolanaError < StandardError; end
  class InsufficientFundsError < SolanaError; end
  class TransactionFailedError < SolanaError; end
  class InvalidAddressError < SolanaError; end
  class VerificationFailedError < SolanaError; end

  # Solana constants
  LAMPORTS_PER_SOL = 1_000_000_000
  TOKEN_DECIMALS = 9  # Standard SPL token decimals
  
  # Transaction confirmation levels
  CONFIRMATION_LEVELS = %w[processed confirmed finalized].freeze

  class << self
    # === CONFIGURATION ===
    
    def config
      @config ||= begin
        config_file = Rails.root.join('config', 'solana_token.yml')
        if File.exist?(config_file)
          env = mainnet? ? 'mainnet' : 'devnet'
          YAML.load_file(config_file)[env] || {}
        else
          {}
        end
      end
    end

    def rpc_url
      ENV.fetch('SOLANA_RPC_URL', config['network_url'] || 'https://api.devnet.solana.com')
    end

    def treasury_address
      ENV.fetch('SOLANA_TREASURY_ADDRESS', nil) || config['treasury_address'] || raise("SOLANA_TREASURY_ADDRESS not set")
    end

    def token_mint
      ENV.fetch('SOLANA_TOKEN_MINT', nil) || config['token_mint'] || raise("SOLANA_TOKEN_MINT not set")
    end

    def treasury_token_account
      ENV.fetch('SOLANA_TREASURY_TOKEN_ACCOUNT', nil) || config['treasury_token_account']
    end

    def mainnet?
      (ENV['SOLANA_RPC_URL'] || '').include?('mainnet')
    end

    def devnet?
      !mainnet?
    end

    # === BALANCE CHECKS ===

    # Get SOL balance for an address
    def get_sol_balance(address)
      validate_address!(address)
      
      response = rpc_request('getBalance', [address])
      lamports = response.dig('result', 'value') || 0
      lamports.to_f / LAMPORTS_PER_SOL
    end

    # Get AMOS token balance for an address
    def get_token_balance(address)
      validate_address!(address)
      
      # Get associated token account
      ata = get_associated_token_address(address)
      
      response = rpc_request('getTokenAccountBalance', [ata])
      
      if response['error']
        # Account doesn't exist = 0 balance
        return 0.0 if response['error']['message']&.include?('could not find account')
        raise SolanaError, response['error']['message']
      end
      
      amount = response.dig('result', 'value', 'uiAmount') || 0
      amount.to_f
    end

    # Get treasury token balance
    def treasury_balance
      get_token_balance(treasury_address)
    end

    # === TOKEN TRANSFERS ===

    # Send tokens from treasury to user wallet
    # Returns transaction signature
    def send_tokens(to_address:, amount:, claim_id: nil)
      validate_address!(to_address)
      raise InsufficientFundsError, "Amount must be positive" if amount <= 0
      
      # Check treasury balance
      treasury = treasury_balance
      if treasury < amount
        raise InsufficientFundsError, "Treasury has #{treasury} tokens, requested #{amount}"
      end

      Rails.logger.info "[SOLANA] Sending #{amount} tokens to #{to_address}"

      # Build and send transaction
      begin
        signature = execute_token_transfer(
          from: treasury_address,
          to: to_address,
          amount: amount,
          memo: claim_id ? "AMOS Claim ##{claim_id}" : nil
        )

        Rails.logger.info "[SOLANA] Transaction sent: #{signature}"
        
        # Wait for confirmation
        confirmed = wait_for_confirmation(signature, level: 'confirmed')
        
        unless confirmed
          raise TransactionFailedError, "Transaction not confirmed: #{signature}"
        end

        Rails.logger.info "[SOLANA] Transaction confirmed: #{signature}"
        signature
        
      rescue => e
        Rails.logger.error "[SOLANA] Transfer failed: #{e.message}"
        raise TransactionFailedError, e.message
      end
    end

    # === DEPOSIT VERIFICATION ===

    # Verify an incoming deposit transaction
    def verify_deposit(transaction_signature:, expected_amount:, expected_from:)
      Rails.logger.info "[SOLANA] Verifying deposit: #{transaction_signature}"

      # Get transaction details
      tx = get_transaction(transaction_signature)
      
      unless tx
        raise VerificationFailedError, "Transaction not found: #{transaction_signature}"
      end

      # Check transaction succeeded
      unless tx.dig('meta', 'err').nil?
        raise VerificationFailedError, "Transaction failed on-chain"
      end

      # Parse token transfer details
      transfer = parse_token_transfer(tx)
      
      unless transfer
        raise VerificationFailedError, "No token transfer found in transaction"
      end

      # Verify sender
      unless transfer[:from] == expected_from
        raise VerificationFailedError, "Sender mismatch. Expected: #{expected_from}, Got: #{transfer[:from]}"
      end

      # Verify recipient is treasury
      unless transfer[:to] == treasury_address
        raise VerificationFailedError, "Recipient is not treasury. Got: #{transfer[:to]}"
      end

      # Verify amount (allow small variance for fees)
      if (transfer[:amount] - expected_amount).abs > 0.000001
        raise VerificationFailedError, "Amount mismatch. Expected: #{expected_amount}, Got: #{transfer[:amount]}"
      end

      # Verify token mint
      unless transfer[:mint] == token_mint
        raise VerificationFailedError, "Wrong token. Expected: #{token_mint}, Got: #{transfer[:mint]}"
      end

      Rails.logger.info "[SOLANA] Deposit verified: #{expected_amount} tokens from #{expected_from}"

      {
        verified: true,
        signature: transaction_signature,
        amount: transfer[:amount],
        from: transfer[:from],
        to: transfer[:to],
        slot: tx['slot'],
        block_time: tx['blockTime']
      }
    end

    # === TRANSACTION STATUS ===

    def get_transaction(signature)
      response = rpc_request('getTransaction', [
        signature,
        { encoding: 'jsonParsed', maxSupportedTransactionVersion: 0 }
      ])
      
      response['result']
    end

    def get_transaction_status(signature)
      response = rpc_request('getSignatureStatuses', [[signature]])
      status = response.dig('result', 'value', 0)
      
      return nil unless status
      
      {
        slot: status['slot'],
        confirmations: status['confirmations'],
        confirmed: status['confirmationStatus'] == 'confirmed' || status['confirmationStatus'] == 'finalized',
        finalized: status['confirmationStatus'] == 'finalized',
        error: status['err']
      }
    end

    def wait_for_confirmation(signature, level: 'confirmed', timeout: 60)
      start_time = Time.current
      
      loop do
        status = get_transaction_status(signature)
        
        if status
          return false if status[:error]  # Transaction failed
          
          case level
          when 'processed'
            return true
          when 'confirmed'
            return true if status[:confirmed]
          when 'finalized'
            return true if status[:finalized]
          end
        end
        
        if Time.current - start_time > timeout
          Rails.logger.warn "[SOLANA] Confirmation timeout for #{signature}"
          return false
        end
        
        sleep 1
      end
    end

    # === WALLET VERIFICATION ===

    # Generate a message for wallet ownership verification
    def generate_verification_message(user_id)
      timestamp = Time.current.to_i
      nonce = SecureRandom.hex(16)
      
      message = "Verify AMOS wallet ownership\n\n" \
                "User ID: #{user_id}\n" \
                "Timestamp: #{timestamp}\n" \
                "Nonce: #{nonce}\n\n" \
                "Sign this message to link your Solana wallet to your AMOS account."
      
      { message: message, nonce: nonce, timestamp: timestamp }
    end

    # Verify a signed message from wallet
    def verify_wallet_signature(address:, message:, signature:)
      validate_address!(address)
      
      begin
        # Decode base58 signature and public key
        sig_bytes = Base58.base58_to_binary(signature, :bitcoin)
        pubkey_bytes = Base58.base58_to_binary(address, :bitcoin)
        
        # Verify using Ed25519
        verify_key = Ed25519::VerifyKey.new(pubkey_bytes)
        verify_key.verify(sig_bytes, message)
        
        true
      rescue Ed25519::VerifyError
        false
      rescue => e
        Rails.logger.error "[SOLANA] Signature verification error: #{e.message}"
        false
      end
    end

    # === UTILITY METHODS ===

    def validate_address!(address)
      unless address.match?(/\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/)
        raise InvalidAddressError, "Invalid Solana address: #{address}"
      end
    end

    def valid_address?(address)
      return false if address.nil? || address.empty?
      address.match?(/\A[1-9A-HJ-NP-Za-km-z]{32,44}\z/)
    end

    # Get associated token account address for a wallet
    def get_associated_token_address(wallet_address)
      # This is a simplified version - in production use proper ATA derivation
      response = rpc_request('getTokenAccountsByOwner', [
        wallet_address,
        { mint: token_mint },
        { encoding: 'jsonParsed' }
      ])
      
      accounts = response.dig('result', 'value') || []
      accounts.first&.dig('pubkey')
    end

    # === PUBLIC STATS ===

    def public_stats
      {
        network: mainnet? ? 'mainnet' : 'devnet',
        token_mint: token_mint,
        treasury_address: treasury_address,
        treasury_balance: treasury_balance,
        total_claimed: TokenClaim.completed.sum(:amount),
        total_deposited: TokenDeposit.completed.sum(:amount),
        pending_claims: TokenClaim.processing.count,
        last_claim_at: TokenClaim.completed.maximum(:confirmed_at),
        last_deposit_at: TokenDeposit.completed.maximum(:confirmed_at)
      }
    end

    private

    def rpc_request(method, params = [])
      body = {
        jsonrpc: '2.0',
        id: SecureRandom.uuid,
        method: method,
        params: params
      }

      response = HTTParty.post(
        rpc_url,
        headers: { 'Content-Type' => 'application/json' },
        body: body.to_json,
        timeout: 30
      )

      JSON.parse(response.body)
    rescue => e
      Rails.logger.error "[SOLANA] RPC error: #{e.message}"
      raise SolanaError, "RPC request failed: #{e.message}"
    end

    def execute_token_transfer(from:, to:, amount:, memo: nil)
      # In production, this would:
      # 1. Build a Solana transaction with SPL token transfer instruction
      # 2. Sign with treasury private key
      # 3. Send to network
      #
      # For now, we'll use a simplified approach via RPC
      # In production, use solana-ruby gem or external signing service
      
      # This is a placeholder - actual implementation requires:
      # - Building raw transaction
      # - Getting recent blockhash
      # - Signing with Ed25519
      # - Serializing and sending
      
      Rails.logger.info "[SOLANA] Would transfer #{amount} from #{from} to #{to}"
      
      # For development/testing, simulate the transfer
      if devnet?
        # On devnet, you might use a signing service or CLI
        simulate_transfer(to, amount, memo)
      else
        # On mainnet, use proper signing
        raise SolanaError, "Mainnet transfers require proper key management"
      end
    end

    def simulate_transfer(to, amount, memo)
      # Simulation for devnet testing
      # Returns a fake signature
      Rails.logger.warn "[SOLANA] SIMULATED transfer - devnet only"
      "sim_#{SecureRandom.hex(32)}"
    end

    def parse_token_transfer(transaction)
      # Parse SPL token transfer from transaction
      instructions = transaction.dig('transaction', 'message', 'instructions') || []
      
      instructions.each do |ix|
        parsed = ix['parsed']
        next unless parsed.is_a?(Hash)
        next unless parsed['type'] == 'transfer' || parsed['type'] == 'transferChecked'
        
        info = parsed['info']
        next unless info
        
        return {
          from: info['authority'] || info['source'],
          to: info['destination'],
          amount: (info['amount'] || info['tokenAmount']&.dig('uiAmount')).to_f,
          mint: info['mint']
        }
      end
      
      nil
    end
  end
end
