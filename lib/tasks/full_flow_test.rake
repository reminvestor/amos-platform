# frozen_string_literal: true

namespace :test_flow do
  desc "Test complete user journey: Referral → Contribution → Tokens"
  task full_journey: :environment do
    puts "\n" + "=" * 70
    puts "🎯 FULL USER JOURNEY TEST"
    puts "   Referral → Ticket → Bounty → Work → Tokens"
    puts "=" * 70

    # Setup
    entity = Entity.first
    unless entity
      puts "❌ No entity found. Run: rails db:seed"
      exit 1
    end

    # Create or find users
    referrer = User.find_or_create_by!(email: "referrer-test@example.com") do |u|
      u.first_name = "Test"
      u.last_name = "Referrer"
      u.entity = entity
      u.password = "password123" if u.respond_to?(:password=)
    end

    builder = User.find_or_create_by!(email: "builder-test@example.com") do |u|
      u.first_name = "Test"
      u.last_name = "Builder"
      u.entity = entity
      u.password = "password123" if u.respond_to?(:password=)
    end

    new_user = User.find_or_create_by!(email: "newuser-test-#{Time.now.to_i}@example.com") do |u|
      u.first_name = "New"
      u.last_name = "User"
      u.entity = entity
      u.password = "password123" if u.respond_to?(:password=)
    end

    puts "\n📌 Entity: #{entity.name}"
    puts "📌 Referrer: #{referrer.email}"
    puts "📌 Builder: #{builder.email}"
    puts "📌 New User: #{new_user.email}"

    # ─────────────────────────────────────────────────────────────────────────
    # PART 1: SALES/REFERRAL FLOW
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "PART 1: REFERRAL FLOW (Sales)"
    puts "─" * 70

    # Check if affiliate system exists
    if defined?(AffiliateReferral)
      referral = AffiliateReferral.create!(
        referrer: referrer,
        referred_user: new_user,
        entity: entity,
        status: 'converted'
      )
      puts "✅ Created referral: #{referrer.email} → #{new_user.email}"

      # Calculate points for this referral
      sales_points = ContributionRewardCalculator.calculate_sales_points(users_signed_up: 1)
      puts "   Points earned: #{sales_points} (1 user = 1 point)"
    else
      puts "⚠️  AffiliateReferral model not found, simulating..."
      sales_points = 1
      puts "   Simulated points: #{sales_points}"
    end

    # ─────────────────────────────────────────────────────────────────────────
    # PART 2: BUG REPORT → BOUNTY FLOW
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "PART 2: TICKET → BOUNTY FLOW"
    puts "─" * 70

    # New user reports a bug
    ticket = SupportTicket.create!(
      entity: entity,
      user: new_user,
      title: "[TEST] API returns 500 on large file upload",
      description: "When uploading files > 10MB, the API crashes with a 500 error. Stack trace attached.",
      source: 'user_reported',
      priority: 'high',
      category: 'bug'
    )
    puts "✅ New user reported bug: #{ticket.ticket_number}"

    # Convert to bounty
    bounty = Bounty.create!(
      entity: entity,
      support_ticket: ticket,
      title: ticket.title,
      description: ticket.description,
      bounty_type: 'bug',
      points: 150,
      ai_scoring_rationale: "High priority bug affecting file uploads",
      source: 'support_ticket',
      urgency_score: 8,
      impact_score: 7
    )
    puts "✅ Bounty created: ##{bounty.id} (#{bounty.points} points)"

    # ─────────────────────────────────────────────────────────────────────────
    # PART 3: BUILDER CLAIMS AND FIXES
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "PART 3: BUILDER CLAIMS BOUNTY"
    puts "─" * 70

    bounty.claim!(builder)
    puts "✅ Builder claimed bounty"

    bounty.start_work!
    puts "✅ Work started"

    bounty.submit!(
      notes: "Fixed the file upload issue. The problem was in the multipart parser - it wasn't handling chunked uploads correctly. Added streaming support for large files.",
      pr_url: "https://github.com/NuvolaNetworks/agent_marketing/pull/#{rand(100..999)}",
      commit_sha: SecureRandom.hex(20)
    )
    puts "✅ Work submitted with PR evidence"
    puts "   PR: #{bounty.pr_url}"

    # ─────────────────────────────────────────────────────────────────────────
    # PART 4: APPROVAL → CONTRIBUTION → TOKEN STAKE
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "PART 4: APPROVAL → TOKENS"
    puts "─" * 70

    # Check initial token state
    initial_stakes = TokenStake.where(user: builder).count
    initial_amount = TokenStake.where(user: builder).sum(:current_amount)

    bounty.approve!(
      reviewer: referrer,  # Referrer reviews (or could be AMOS)
      final_points: 165,   # +10% for quality
      notes: "Great fix! Clean implementation."
    )
    puts "✅ Bounty approved (165 points after quality bonus)"

    # Check contribution
    contribution = Contribution.where(user: builder).order(created_at: :desc).first
    if contribution
      puts "✅ Contribution created:"
      puts "   ID: #{contribution.id}"
      puts "   Type: #{contribution.contribution_type}"
      puts "   Stake Value: #{contribution.stake_value}"
      puts "   Work Evidence: #{contribution.work_evidence_display}"
    end

    # Check token stake
    new_stakes = TokenStake.where(user: builder).count
    new_amount = TokenStake.where(user: builder).sum(:current_amount)

    if new_stakes > initial_stakes
      stake = TokenStake.where(user: builder).order(created_at: :desc).first
      puts "✅ Token stake awarded!"
      puts "   Initial Amount: #{stake.initial_amount} AMOS"
      puts "   Current Amount: #{stake.current_amount} AMOS"
      puts "   Stake Type: #{stake.stake_type}"
      puts "   Category: #{stake.category}"
      puts "   Grace Period: #{stake.grace_period_days_remaining} days remaining"
    else
      puts "⚠️  No new token stake created (check TokenStake.create_contribution_stake!)"
    end

    # ─────────────────────────────────────────────────────────────────────────
    # PART 5: DAILY POOL CALCULATION
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "PART 5: DAILY POOL DISTRIBUTION"
    puts "─" * 70

    # Simulate daily pool
    total_points_today = 150 + sales_points  # Bounty + referral
    builder_points = 150  # From bounty
    referrer_points = sales_points  # From referral

    daily_emission = ContributionRewardCalculator::DAILY_EMISSION

    builder_tokens = ContributionRewardCalculator.calculate_reward(
      your_points: builder_points,
      total_points_today: total_points_today
    )

    referrer_tokens = ContributionRewardCalculator.calculate_reward(
      your_points: referrer_points,
      total_points_today: total_points_today
    )

    puts "📊 Daily Pool Distribution:"
    puts "   Daily Emission: #{daily_emission} AMOS"
    puts "   Total Points Today: #{total_points_today}"
    puts ""
    puts "   Builder (#{builder_points} points):"
    puts "     Share: #{(builder_points.to_f / total_points_today * 100).round(1)}%"
    puts "     Tokens: #{builder_tokens} AMOS"
    puts ""
    puts "   Referrer (#{referrer_points} points):"
    puts "     Share: #{(referrer_points.to_f / total_points_today * 100).round(1)}%"
    puts "     Tokens: #{referrer_tokens} AMOS"

    # ─────────────────────────────────────────────────────────────────────────
    # PART 6: TOKEN STATE SUMMARY
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "PART 6: FINAL TOKEN STATE"
    puts "─" * 70

    [referrer, builder].each do |user|
      stakes = TokenStake.where(user: user)
      puts "\n👤 #{user.email}:"
      puts "   Total Stakes: #{stakes.count}"
      puts "   Total Amount: #{stakes.sum(:current_amount)} AMOS"
      
      stakes.each do |stake|
        puts "   └─ #{stake.stake_type}: #{stake.current_amount} AMOS (#{stake.category})"
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # SUMMARY
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "=" * 70
    puts "🎉 FULL JOURNEY COMPLETE!"
    puts "=" * 70
    puts "\nWhat happened:"
    puts "  1. Referrer invited new user → earned #{sales_points} point(s)"
    puts "  2. New user reported bug → created ticket #{ticket.ticket_number}"
    puts "  3. Ticket → Bounty ##{bounty.id} (#{bounty.points} points)"
    puts "  4. Builder fixed bug → submitted PR #{bounty.pr_number}"
    puts "  5. Approved → Contribution + Token Stake created"
    puts "  6. Daily pool: #{builder_tokens} AMOS to builder"
    puts "\n⚠️  Note: Actual on-chain token transfers require Solana mainnet"
    puts "   The internal ledger (TokenStake) is updated, but no blockchain tx yet."
    puts "\n"
  end

  desc "Show current token economy state"
  task token_state: :environment do
    puts "\n" + "=" * 70
    puts "📊 TOKEN ECONOMY STATE"
    puts "=" * 70

    puts "\n📈 Overview:"
    puts "   Total Stakes: #{TokenStake.count}"
    puts "   Total Staked: #{TokenStake.sum(:current_amount).round(2)} AMOS"
    puts "   Active Stakes: #{TokenStake.active.count}"

    puts "\n📋 By Type:"
    TokenStake.group(:stake_type).sum(:current_amount).each do |type, amount|
      puts "   #{type}: #{amount.round(2)} AMOS"
    end

    puts "\n📋 By Category:"
    TokenStake.group(:category).sum(:current_amount).each do |cat, amount|
      puts "   #{cat || 'none'}: #{amount.round(2)} AMOS"
    end

    puts "\n🏆 Top Token Holders:"
    TokenStake.select('user_id, SUM(current_amount) as total')
              .group(:user_id)
              .order('total DESC')
              .limit(10)
              .each_with_index do |stake, i|
      user = User.find_by(id: stake.user_id)
      puts "   #{i + 1}. #{user&.email || 'Unknown'}: #{stake.total.round(2)} AMOS"
    end

    puts "\n📋 Recent Stakes:"
    TokenStake.order(created_at: :desc).limit(5).each do |stake|
      puts "   #{stake.created_at.strftime('%Y-%m-%d')}: #{stake.initial_amount} AMOS (#{stake.stake_type})"
    end

    puts "\n"
  end
end
