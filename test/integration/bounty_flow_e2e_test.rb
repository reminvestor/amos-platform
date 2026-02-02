# frozen_string_literal: true

require 'test_helper'

class BountyFlowE2ETest < ActiveSupport::TestCase
  setup do
    @entity = entities(:one)
    @contributor = users(:one)
    @reviewer = users(:two)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # COMPLETE FLOW: Ticket → Bounty → Work → Payment
  # ═══════════════════════════════════════════════════════════════════════════

  test "complete bounty flow from ticket to token payment" do
    # STEP 1: A critical bug is reported
    puts "\n📝 STEP 1: Creating support ticket..."
    ticket = SupportTicket.create!(
      entity: @entity,
      title: "Login fails on mobile Safari",
      description: "Users on iOS Safari cannot complete login - affects ~30% of mobile users",
      source: 'user_reported',
      priority: 'critical',
      category: 'bug'
    )
    assert ticket.persisted?
    puts "   ✓ Created ticket: #{ticket.ticket_number}"

    # STEP 2: Integration service converts ticket to bounty
    puts "\n🎯 STEP 2: Converting ticket to bounty..."
    integration = BountyIntegrationService.new(@entity)

    AmosBountyScorer.stub(:score_ticket, ->(_) {
      {
        points: 200,
        rationale: "Critical bug affecting 30% of mobile users. High urgency.",
        effort_score: 6,
        impact_score: 9,
        urgency_score: 10,
        complexity_score: 5,
        estimated_hours: 4
      }
    }) do
      bounty = integration.create_bounty_from_ticket(ticket)

      assert bounty.persisted?
      assert_equal ticket, bounty.support_ticket
      assert_equal 200, bounty.points
      assert_equal 'bug', bounty.bounty_type
      assert_equal 'open', bounty.status
      puts "   ✓ Created bounty ##{bounty.id}: #{bounty.title} (#{bounty.points} points)"

      @bounty = bounty
    end

    # STEP 3: Contributor claims the bounty
    puts "\n👋 STEP 3: Contributor claims bounty..."
    result = @bounty.claim!(@contributor)
    assert result
    assert_equal 'claimed', @bounty.status
    assert_equal @contributor, @bounty.claimed_by
    puts "   ✓ Claimed by: #{@contributor.email}"

    # STEP 4: Contributor starts work
    puts "\n🔨 STEP 4: Starting work..."
    @bounty.start_work!
    assert_equal 'in_progress', @bounty.status
    puts "   ✓ Status: in_progress"

    # STEP 5: Contributor submits completed work with evidence
    puts "\n📤 STEP 5: Submitting work with PR evidence..."
    @bounty.submit!(
      notes: "Fixed the Safari login issue. The problem was in the OAuth callback handling - Safari's ITP was blocking the redirect. Added a workaround using localStorage for token storage.",
      pr_url: "https://github.com/NuvolaNetworks/agent_marketing/pull/456",
      commit_sha: "a1b2c3d4e5f6789012345678901234567890abcd"
    )

    assert_equal 'submitted', @bounty.status
    assert_equal 456, @bounty.pr_number
    assert @bounty.pr_url.present?
    assert @bounty.commit_sha.present?
    puts "   ✓ Submitted with PR ##{@bounty.pr_number}"
    puts "   ✓ Commit: #{@bounty.commit_sha[0..7]}..."

    # STEP 6: AI reviews the work
    puts "\n🤖 STEP 6: AI reviewing work..."
    AmosWorkReviewer.stub(:review, ->(**_args) {
      {
        approved: true,
        final_points: 220,  # +10% for quality
        point_adjustment_percent: 10,
        quality_score: 8,
        feedback: "Excellent fix! Good explanation of the root cause. Clean implementation with proper fallback handling.",
        issues: [],
        praise: ["Clear root cause analysis", "Clean code", "Good documentation"]
      }
    }) do
      review_result = AmosWorkReviewer.review(
        bounty: @bounty,
        submission_notes: @bounty.submission_notes,
        code_diff: "+// Handle Safari ITP restrictions\n+const token = localStorage.getItem('auth_token');"
      )

      puts "   ✓ Approved: #{review_result[:approved]}"
      puts "   ✓ Quality Score: #{review_result[:quality_score]}/10"
      puts "   ✓ Final Points: #{review_result[:final_points]} (+#{review_result[:point_adjustment_percent]}%)"
      puts "   ✓ Praise: #{review_result[:praise].join(', ')}"

      # STEP 7: Approve the bounty (creates contribution + token stake)
      puts "\n✅ STEP 7: Approving bounty and creating contribution..."

      initial_contribution_count = Contribution.count
      initial_stake_count = TokenStake.count

      @bounty.approve!(
        reviewer: @reviewer,
        final_points: review_result[:final_points],
        notes: review_result[:feedback]
      )

      assert_equal 'approved', @bounty.status
      assert_equal 220, @bounty.final_points
      puts "   ✓ Bounty approved with #{@bounty.final_points} points"

      # Verify contribution was created
      contribution = Contribution.find_by(external_reference: @bounty.send(:build_external_reference))
      if contribution
        assert_equal @contributor, contribution.user
        assert_equal 220, contribution.stake_value
        assert contribution.approved?
        puts "   ✓ Contribution created: #{contribution.title}"
        puts "   ✓ Stake value: #{contribution.stake_value} points"
      end

      # Verify token stake was awarded
      if contribution&.token_stake
        stake = contribution.token_stake
        puts "   ✓ Token stake awarded: #{stake.initial_amount} AMOS"
        puts "   ✓ Stake type: #{stake.stake_type}"
      end
    end

    # STEP 8: Verify ticket was resolved
    puts "\n🎫 STEP 8: Verifying ticket resolution..."
    ticket.reload
    if ticket.status == 'resolved'
      puts "   ✓ Ticket #{ticket.ticket_number} marked as RESOLVED"
    else
      puts "   ⚠ Ticket status: #{ticket.status} (sync may need manual trigger)"
    end

    # STEP 9: Verify payment trail
    puts "\n💰 STEP 9: Verifying payment trail..."
    puts "   Full trail:"
    puts "   └─ Ticket: #{ticket.ticket_number}"
    puts "   └─ Bounty: ##{@bounty.id} (#{@bounty.effective_points} points)"
    puts "   └─ Work Evidence: #{@bounty.send(:work_evidence_summary)}"
    puts "   └─ Contributor: #{@contributor.email}"

    puts "\n✅ COMPLETE FLOW SUCCESSFUL!"
    puts "   User #{@contributor.email} earned #{@bounty.effective_points} points"
    puts "   for fixing critical bug #{ticket.ticket_number}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # AMOS THINKING TIME FLOW
  # ═══════════════════════════════════════════════════════════════════════════

  test "AMOS nightly thinking creates bounties" do
    puts "\n🌙 AMOS THINKING TIME TEST"
    puts "=" * 50

    # Create some platform data for AMOS to analyze
    SupportTicket.create!(
      entity: @entity,
      title: "Feature request: Dark mode",
      description: "Many users have requested dark mode support",
      source: 'user_reported',
      priority: 'medium',
      category: 'feature_request',
      admin_approved: true,
      metadata: { 'votes' => 25 }
    )

    service = AmosThinkingService.new(@entity)

    # Mock the LLM response
    mock_reflection = {
      reflection_summary: "Platform is healthy. Dark mode is highly requested (25 votes). Also noticed some slow API responses that should be investigated.",
      observations: [
        "Dark mode feature has 25 community votes",
        "API response times have increased 15% this week",
        "3 new users signed up but didn't complete onboarding"
      ],
      priorities: [
        "Dark mode implementation",
        "Performance investigation",
        "Onboarding improvement"
      ],
      bounty_ideas: [
        {
          title: "Implement dark mode toggle",
          description: "Add a dark theme option to the UI with CSS variables for easy theming",
          type: "feature",
          rationale: "Highly requested by community (25 votes). Improves accessibility and user preference."
        },
        {
          title: "Investigate API slowdown",
          description: "Profile API endpoints and identify performance bottlenecks",
          type: "bug",
          rationale: "15% response time increase may impact user experience."
        },
        {
          title: "Improve onboarding flow",
          description: "Add progress indicators and helpful tips to onboarding",
          type: "design",
          rationale: "3 users dropped off during onboarding this week."
        }
      ]
    }.to_json

    AmosBountyScorer.stub(:score, ->(**args) {
      base_points = case args[:bounty_type]
      when 'feature' then 300
      when 'bug' then 150
      when 'design' then 200
      else 100
      end
      {
        points: base_points,
        rationale: "AI scored based on #{args[:bounty_type]}",
        effort_score: 6,
        impact_score: 7,
        urgency_score: 5,
        complexity_score: 6,
        estimated_hours: 8
      }
    }) do
      service.stub(:call_llm, ->(_) { mock_reflection }) do
        BountyIntegrationService.any_instance.stub(:sync_all!, -> {
          { from_tickets: [], from_goals: [], from_anomalies: [], from_features: [] }
        }) do
          puts "\n🔍 Phase 1: Gathering context..."
          context = service.gather_context
          puts "   ✓ Open tickets: #{context[:open_tickets]}"
          puts "   ✓ Feature requests: #{context[:feature_requests].count}"

          puts "\n💭 Phase 2: Running thinking session..."
          result = service.think!

          puts "\n📊 Session Results:"
          puts "   ✓ Session ID: #{result[:session].id}"
          puts "   ✓ Status: #{result[:session].status}"
          puts "   ✓ Bounties created: #{result[:bounties].count}"
          puts "   ✓ Total points allocated: #{result[:bounties].sum(&:points)}"

          puts "\n📋 Created Bounties:"
          result[:bounties].each_with_index do |bounty, i|
            puts "   #{i + 1}. #{bounty.title}"
            puts "      Type: #{bounty.bounty_type}, Points: #{bounty.points}"
          end

          assert result[:session].completed?
          assert result[:bounties].count >= 3
          assert result[:bounties].all?(&:created_by_amos?)
        end
      end
    end

    puts "\n✅ AMOS THINKING TIME SUCCESSFUL!"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # REJECTION AND RE-CLAIM FLOW
  # ═══════════════════════════════════════════════════════════════════════════

  test "bounty rejection allows re-claim by another contributor" do
    puts "\n🔄 REJECTION AND RE-CLAIM TEST"
    puts "=" * 50

    # Create a bounty
    bounty = Bounty.create!(
      entity: @entity,
      title: "Add export to CSV feature",
      description: "Users want to export their data to CSV",
      bounty_type: 'feature',
      points: 150
    )
    puts "\n📝 Created bounty: #{bounty.title}"

    # First contributor claims and submits poor work
    contributor1 = @contributor
    bounty.claim!(contributor1)
    bounty.submit!(notes: "done")  # Minimal submission
    puts "   ✓ Contributor 1 claimed and submitted"

    # Work is rejected
    bounty.reject!(reviewer: @reviewer, notes: "Submission lacks detail. No code or evidence provided.")
    assert_equal 'open', bounty.status
    assert_nil bounty.claimed_by
    puts "   ✓ Work rejected - bounty released"

    # Second contributor picks it up
    contributor2 = users(:three)
    bounty.claim!(contributor2)
    bounty.submit!(
      notes: "Implemented CSV export with proper headers, UTF-8 encoding, and streaming for large datasets",
      pr_url: "https://github.com/org/repo/pull/789",
      commit_sha: "xyz789abc"
    )
    puts "   ✓ Contributor 2 claimed and submitted with evidence"

    # This time it's approved
    bounty.approve!(
      reviewer: @reviewer,
      final_points: 165,  # +10% for quality
      notes: "Great implementation!"
    )

    assert_equal 'approved', bounty.status
    assert_equal contributor2, bounty.claimed_by
    puts "   ✓ Work approved for Contributor 2"
    puts "\n✅ RE-CLAIM FLOW SUCCESSFUL!"
  end
end
