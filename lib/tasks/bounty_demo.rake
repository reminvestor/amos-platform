# frozen_string_literal: true

namespace :bounty do
  desc "Demo the complete bounty flow end-to-end"
  task demo: :environment do
    puts "\n" + "=" * 70
    puts "🚀 AMOS BOUNTY SYSTEM DEMO"
    puts "=" * 70

    # Find or create an entity
    entity = Entity.first
    unless entity
      puts "❌ No entities found. Please create an entity first."
      exit 1
    end

    user = entity.users.first
    unless user
      puts "❌ No users found. Please create a user first."
      exit 1
    end

    puts "\n📌 Using entity: #{entity.name}"
    puts "📌 Using user: #{user.email}"

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 1: Create a support ticket
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "STEP 1: Creating Support Ticket"
    puts "─" * 70

    ticket = SupportTicket.create!(
      entity: entity,
      title: "[DEMO] Login button not working on Firefox",
      description: "Users report that the login button is unresponsive on Firefox. Console shows a JavaScript error.",
      source: 'user_reported',
      priority: 'high',
      category: 'bug'
    )

    puts "✅ Created ticket: #{ticket.ticket_number}"
    puts "   Title: #{ticket.title}"
    puts "   Priority: #{ticket.priority}"
    puts "   Status: #{ticket.status}"

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 2: Convert ticket to bounty
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "STEP 2: Converting Ticket to Bounty (AI Scoring)"
    puts "─" * 70

    integration = BountyIntegrationService.new(entity)

    # Use real AI scoring if available, fallback otherwise
    begin
      bounty = integration.create_bounty_from_ticket(ticket)
    rescue => e
      puts "⚠️  AI scoring unavailable, using fallback: #{e.message}"
      bounty = Bounty.create_from_ticket!(
        ticket,
        points: 150,
        scoring_rationale: "Fallback scoring for high-priority bug"
      )
    end

    puts "✅ Created bounty ##{bounty.id}"
    puts "   Title: #{bounty.title}"
    puts "   Type: #{bounty.bounty_type}"
    puts "   Points: #{bounty.points}"
    puts "   Scoring: #{bounty.ai_scoring_rationale}"

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 3: Contributor claims bounty
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "STEP 3: Contributor Claims Bounty"
    puts "─" * 70

    bounty.claim!(user)

    puts "✅ Bounty claimed!"
    puts "   Claimed by: #{user.email}"
    puts "   Claimed at: #{bounty.claimed_at}"
    puts "   Status: #{bounty.status}"

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 4: Work in progress
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "STEP 4: Work In Progress"
    puts "─" * 70

    bounty.start_work!

    puts "✅ Work started"
    puts "   Status: #{bounty.status}"

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 5: Submit work with evidence
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "STEP 5: Submit Work with Evidence"
    puts "─" * 70

    bounty.submit!(
      notes: "Fixed the Firefox issue. The problem was an event listener using 'click' instead of 'mousedown' which Firefox handles differently. Updated the login.js file to use a cross-browser compatible approach.",
      pr_url: "https://github.com/NuvolaNetworks/agent_marketing/pull/#{rand(100..999)}",
      commit_sha: SecureRandom.hex(20)
    )

    puts "✅ Work submitted!"
    puts "   Status: #{bounty.status}"
    puts "   PR: #{bounty.pr_url}"
    puts "   Commit: #{bounty.commit_sha[0..7]}..."
    puts "   Notes: #{bounty.submission_notes.truncate(100)}"

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 6: AI Review
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "STEP 6: AI Review"
    puts "─" * 70

    begin
      review = AmosWorkReviewer.review(
        bounty: bounty,
        submission_notes: bounty.submission_notes
      )
    rescue => e
      puts "⚠️  AI review unavailable, using auto-approve: #{e.message}"
      review = {
        approved: true,
        final_points: bounty.points,
        quality_score: 7,
        feedback: "Work accepted",
        issues: [],
        praise: ["Submission received"]
      }
    end

    puts "✅ Review complete!"
    puts "   Approved: #{review[:approved] ? 'YES ✓' : 'NO ✗'}"
    puts "   Quality Score: #{review[:quality_score]}/10"
    puts "   Final Points: #{review[:final_points]}"
    puts "   Feedback: #{review[:feedback]&.truncate(100)}"

    # ─────────────────────────────────────────────────────────────────────────
    # STEP 7: Approve and create contribution
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "─" * 70
    puts "STEP 7: Approve Bounty & Create Contribution"
    puts "─" * 70

    bounty.approve!(
      reviewer: user,  # Self-review for demo
      final_points: review[:final_points],
      notes: review[:feedback]
    )

    puts "✅ Bounty approved!"
    puts "   Status: #{bounty.status}"
    puts "   Final Points: #{bounty.final_points}"

    # Check for contribution
    contribution = Contribution.order(created_at: :desc).first
    if contribution && contribution.external_reference&.include?("bounty:#{bounty.id}")
      puts "\n✅ Contribution created!"
      puts "   ID: #{contribution.id}"
      puts "   Type: #{contribution.contribution_type}"
      puts "   Stake Value: #{contribution.stake_value}"
      puts "   External Ref: #{contribution.external_reference}"

      if contribution.token_stake
        puts "\n✅ Token stake awarded!"
        puts "   Initial Amount: #{contribution.token_stake.initial_amount}"
        puts "   Stake Type: #{contribution.token_stake.stake_type}"
      end
    end

    # ─────────────────────────────────────────────────────────────────────────
    # SUMMARY
    # ─────────────────────────────────────────────────────────────────────────
    puts "\n" + "=" * 70
    puts "🎉 DEMO COMPLETE!"
    puts "=" * 70
    puts "\nFull Payment Trail:"
    puts "  ├─ Ticket: #{ticket.ticket_number}"
    puts "  ├─ Bounty: ##{bounty.id}"
    puts "  ├─ Points: #{bounty.final_points}"
    puts "  ├─ PR: #{bounty.pr_url}"
    puts "  ├─ Commit: #{bounty.commit_sha[0..7]}"
    puts "  └─ Contributor: #{user.email}"
    puts "\n"
  end

  desc "Run AMOS thinking time manually"
  task thinking_time: :environment do
    puts "\n" + "=" * 70
    puts "🌙 AMOS THINKING TIME"
    puts "=" * 70

    entity = Entity.first
    unless entity
      puts "❌ No entities found."
      exit 1
    end

    puts "\n📌 Running for entity: #{entity.name}"
    puts "\n💭 Starting thinking session..."

    service = AmosThinkingService.new(entity)

    begin
      result = service.think!

      puts "\n" + "─" * 70
      puts "SESSION RESULTS"
      puts "─" * 70
      puts "Session ID: #{result[:session].id}"
      puts "Status: #{result[:session].status}"
      puts "Duration: #{result[:session].duration_display}"
      puts "\nReflection Summary:"
      puts result[:reflection][:reflection_summary] || "(no summary)"

      puts "\nBounties Created: #{result[:bounties].count}"
      result[:bounties].each_with_index do |bounty, i|
        puts "  #{i + 1}. #{bounty.title}"
        puts "     Type: #{bounty.bounty_type} | Points: #{bounty.points}"
      end

      puts "\nTotal Points Allocated: #{result[:bounties].sum(&:points)}"

    rescue => e
      puts "❌ Error: #{e.message}"
      puts e.backtrace.first(5).join("\n")
    end

    puts "\n"
  end

  desc "List all open bounties"
  task list: :environment do
    bounties = Bounty.open_bounties.order(points: :desc)

    if bounties.empty?
      puts "No open bounties found."
    else
      puts "\n" + "=" * 70
      puts "📋 OPEN BOUNTIES"
      puts "=" * 70
      puts "\n"

      bounties.each do |bounty|
        puts "━" * 60
        puts "##{bounty.id} | #{bounty.points} pts | #{bounty.bounty_type.upcase}"
        puts "━" * 60
        puts bounty.title
        puts bounty.description&.truncate(200)
        puts "Created: #{bounty.created_at.strftime('%Y-%m-%d')} | By: #{bounty.created_by_amos? ? 'AMOS' : bounty.created_by&.email}"
        puts "\n"
      end

      puts "Total: #{bounties.count} open bounties"
      puts "Total Points: #{bounties.sum(:points)}"
    end
  end
end
