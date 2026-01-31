# frozen_string_literal: true

namespace :solana do
  desc "Test Solana devnet connection and token status"
  task status: :environment do
    puts "\n" + "=" * 70
    puts "🔗 SOLANA CONNECTION STATUS"
    puts "=" * 70

    puts "\n📡 Network Configuration:"
    puts "   RPC URL: #{SolanaTokenService.rpc_url}"
    puts "   Network: #{SolanaTokenService.mainnet? ? '🔴 MAINNET' : '🟢 DEVNET'}"
    puts "   Token Mint: #{SolanaTokenService.token_mint rescue 'NOT SET'}"
    puts "   Treasury: #{SolanaTokenService.treasury_address rescue 'NOT SET'}"

    begin
      puts "\n💰 Treasury Status:"
      balance = SolanaTokenService.treasury_balance
      puts "   Token Balance: #{balance} AMOS"

      sol_balance = SolanaTokenService.get_sol_balance(SolanaTokenService.treasury_address)
      puts "   SOL Balance: #{sol_balance} SOL"

      if sol_balance < 0.01
        puts "   ⚠️  LOW SOL - may not have enough for transaction fees!"
      end

      puts "\n📊 Platform Token Stats:"
      puts "   Total Staked: #{TokenStake.sum(:current_amount).round(2)} AMOS"
      puts "   Active Stakes: #{TokenStake.active.count}"
      puts "   Total Claimed: #{TokenClaim.completed.sum(:amount).round(2)} AMOS"
      puts "   Pending Claims: #{TokenClaim.processing.count}"

      puts "\n✅ Connection successful!"

    rescue => e
      puts "\n❌ Connection failed: #{e.message}"
      puts "   Check your ENV variables:"
      puts "   - SOLANA_RPC_URL"
      puts "   - SOLANA_TOKEN_MINT"
      puts "   - SOLANA_TREASURY_ADDRESS"
    end

    puts "\n"
  end

  desc "Test full claim flow on devnet"
  task test_claim: :environment do
    puts "\n" + "=" * 70
    puts "🧪 DEVNET CLAIM FLOW TEST"
    puts "=" * 70

    unless SolanaTokenService.devnet?
      puts "\n❌ This test is for DEVNET only!"
      puts "   Current network: #{SolanaTokenService.rpc_url}"
      puts "   Set SOLANA_RPC_URL=https://api.devnet.solana.com"
      exit 1
    end

    # Find or create test user
    entity = Entity.first
    user = User.find_by(email: "solana-test@example.com")

    unless user
      puts "\n📝 Creating test user..."
      user = User.create!(
        email: "solana-test@example.com",
        first_name: "Solana",
        last_name: "Tester",
        entity: entity,
        role: "marketer",
        password: "testpassword123"
      )
      puts "   ✅ Created: #{user.email}"
    else
      puts "\n📝 Using existing test user: #{user.email}"
    end

    # Check if user has a wallet connected
    if user.solana_wallet_address.blank?
      puts "\n⚠️  No wallet connected to test user!"
      puts "   You need to connect a Phantom wallet first."
      puts ""
      puts "   Option 1: Set manually in console:"
      puts "   User.find_by(email: 'solana-test@example.com').update!(solana_wallet_address: 'YOUR_PHANTOM_ADDRESS')"
      puts ""
      puts "   Option 2: Connect via UI (see instructions below)"
      puts ""

      # Ask for wallet address
      print "   Enter a Phantom wallet address to continue (or press Enter to skip): "
      wallet = STDIN.gets.chomp

      if wallet.present? && SolanaTokenService.valid_address?(wallet)
        user.update!(solana_wallet_address: wallet)
        puts "   ✅ Wallet connected: #{wallet}"
      else
        puts "   Skipping claim test - no wallet connected."
        exit 0
      end
    end

    puts "\n👛 Wallet: #{user.solana_wallet_address}"

    # Check internal balance
    internal_balance = user.token_stakes.active.sum(:current_amount)
    puts "\n💰 Internal Balance: #{internal_balance} AMOS"

    if internal_balance < TokenClaim::MINIMUM_CLAIM
      puts "\n⚠️  Insufficient balance for claim test!"
      puts "   Minimum claim: #{TokenClaim::MINIMUM_CLAIM} AMOS"
      puts "   Creating test stake..."

      stake = TokenStake.create!(
        user: user,
        entity: entity,
        stake_type: 'contribution',
        category: 'test',
        initial_amount: 200,
        current_amount: 200,
        decay_rate: 0.0,
        earned_at: Time.current
      )

      internal_balance = 200
      puts "   ✅ Created test stake: #{stake.initial_amount} AMOS"
    end

    # Check treasury balance
    puts "\n🏦 Treasury Balance: #{SolanaTokenService.treasury_balance} AMOS"

    # Create claim
    claim_amount = [internal_balance, 100].min
    puts "\n📤 Creating claim for #{claim_amount} AMOS..."

    claim = TokenClaim.create!(
      user: user,
      entity: entity,
      amount: claim_amount,
      wallet_address: user.solana_wallet_address
    )

    puts "   Claim ID: #{claim.id}"
    puts "   Amount: #{claim.amount}"
    puts "   Net (after 1% fee): #{claim.net_amount}"
    puts "   Status: #{claim.status}"

    # Validate claim
    puts "\n🔍 Validating claim..."
    if claim.validate_claim!
      puts "   ✅ Claim validated!"
    else
      puts "   ❌ Validation failed: #{claim.error_message}"
      exit 1
    end

    # Process claim
    puts "\n⚙️  Processing claim (sending to Solana)..."
    claim.start_processing!

    begin
      signature = SolanaTokenService.send_tokens(
        to_address: claim.wallet_address,
        amount: claim.net_amount,
        claim_id: claim.id
      )

      claim.complete!(transaction_signature: signature)
      puts "   ✅ Claim completed!"
      puts "   Transaction: #{signature}"

      if signature.start_with?('sim_')
        puts "\n   ⚠️  This was a SIMULATED transaction (devnet mock)"
        puts "   For real transfers, implement proper Solana signing"
      else
        puts "\n   🔗 View on Solscan:"
        puts "   https://solscan.io/tx/#{signature}?cluster=devnet"
      end

    rescue => e
      claim.fail!(e.message)
      puts "   ❌ Claim failed: #{e.message}"
    end

    # Final status
    puts "\n" + "─" * 70
    puts "FINAL STATUS"
    puts "─" * 70
    puts "Claim ID: #{claim.id}"
    puts "Status: #{claim.status}"
    puts "Amount: #{claim.amount} AMOS"
    puts "Net Amount: #{claim.net_amount} AMOS"
    puts "Wallet: #{claim.wallet_address}"
    puts "Transaction: #{claim.transaction_signature || 'N/A'}"
    puts "User Balance After: #{user.token_stakes.active.sum(:current_amount)} AMOS"

    puts "\n"
  end

  desc "Create test stake for a user (for testing claims)"
  task :create_test_stake, [:email, :amount] => :environment do |t, args|
    email = args[:email] || "solana-test@example.com"
    amount = (args[:amount] || 500).to_f

    user = User.find_by(email: email)
    unless user
      puts "❌ User not found: #{email}"
      exit 1
    end

    stake = TokenStake.create!(
      user: user,
      entity: user.entity,
      stake_type: 'contribution',
      category: 'test',
      initial_amount: amount,
      current_amount: amount,
      decay_rate: 0.0,
      earned_at: Time.current
    )

    puts "✅ Created stake of #{amount} AMOS for #{email}"
    puts "   Total balance now: #{user.token_stakes.active.sum(:current_amount)} AMOS"
  end

  desc "Connect a wallet to a user"
  task :connect_wallet, [:email, :wallet_address] => :environment do |t, args|
    unless args[:email] && args[:wallet_address]
      puts "Usage: rails solana:connect_wallet[email,wallet_address]"
      exit 1
    end

    user = User.find_by(email: args[:email])
    unless user
      puts "❌ User not found: #{args[:email]}"
      exit 1
    end

    unless SolanaTokenService.valid_address?(args[:wallet_address])
      puts "❌ Invalid Solana address: #{args[:wallet_address]}"
      exit 1
    end

    user.update!(solana_wallet_address: args[:wallet_address])
    puts "✅ Connected wallet to #{args[:email]}"
    puts "   Wallet: #{args[:wallet_address]}"
  end
end
