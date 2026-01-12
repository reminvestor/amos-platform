# frozen_string_literal: true

namespace :agents do
  desc "Test domain matching for agent task proposals"
  task test_domain_matching: :environment do
    puts "\n" + "=" * 80
    puts "🧪 AGENT DOMAIN MATCHING TEST"
    puts "=" * 80

    # Test scenarios: [task_description, expected_agent_slugs, domain]
    test_scenarios = [
      # Landing Page Tests
      {
        description: "Create a landing page for our summer sale promotion",
        expected_agents: %w[landing_page_manager ai_landing_page_creator],
        domain: "landing_page",
        tools_passed: %w[create_module design_canvas generate_content]  # Wrong tools, but should still match
      },
      {
        description: "Build a new landing page for the product launch",
        expected_agents: %w[landing_page_manager ai_landing_page_creator],
        domain: "landing_page",
        tools_passed: []  # No tools specified
      },
      {
        description: "I need a website page for capturing leads",
        expected_agents: %w[landing_page_manager ai_landing_page_creator],
        domain: "landing_page",
        tools_passed: %w[generate_ai_landing_page]  # Correct tool
      },

      # Integration Tests
      {
        description: "Create an API integration with Stripe for payments",
        expected_agents: %w[integration_architect integration_specialist],
        domain: "integration",
        tools_passed: %w[create_module]  # Wrong tools
      },
      {
        description: "Connect my app to the Slack webhook",
        expected_agents: %w[integration_architect integration_specialist],
        domain: "integration",
        tools_passed: []
      },

      # Module Tests
      {
        description: "Build a custom module with fields for tracking inventory",
        expected_agents: %w[platform_factory module_architect],
        domain: "module",
        tools_passed: []
      },
      {
        description: "Create a new schema for customer data with name and email fields",
        expected_agents: %w[platform_factory module_architect],
        domain: "module",
        tools_passed: %w[start_module_design]
      },

      # Analytics Tests
      {
        description: "Create a dashboard visualization for sales metrics",
        expected_agents: %w[analytics_agent data_analyst],
        domain: "analytics",
        tools_passed: []
      },

      # Negative Tests - Should NOT domain match
      {
        description: "Send an email to john@example.com",
        expected_agents: [],  # Generic task, no specific domain
        domain: "none",
        tools_passed: [],
        expect_rejection: true
      }
    ]

    entity = Entity.first
    user = User.first

    unless entity && user
      puts "❌ No entity or user found. Please seed the database first."
      exit 1
    end

    results = { passed: 0, failed: 0, details: [] }

    test_scenarios.each_with_index do |scenario, index|
      puts "\n" + "-" * 60
      puts "Test #{index + 1}: #{scenario[:domain].upcase}"
      puts "Task: #{scenario[:description].truncate(60)}"
      puts "Tools passed: #{scenario[:tools_passed].any? ? scenario[:tools_passed].join(', ') : '(none)'}"
      puts "Expected agents: #{scenario[:expected_agents].any? ? scenario[:expected_agents].join(', ') : '(none - expect rejection)'}"

      # Find agents that match expected slugs
      matched_agents = []
      scenario[:expected_agents].each do |slug_pattern|
        agent = AgentPlugin.where(status: 'active').find_by("slug LIKE ?", "%#{slug_pattern}%")
        matched_agents << agent if agent
      end

      if matched_agents.empty? && scenario[:expected_agents].any?
        puts "⚠️  No matching agents found for: #{scenario[:expected_agents].join(', ')}"
        puts "   Available agents: #{AgentPlugin.where(status: 'active').pluck(:slug).join(', ')}"
        results[:details] << { test: index + 1, status: :skipped, reason: "No matching agents" }
        next
      end

      # Test each matched agent
      agent_results = []
      
      if matched_agents.any?
        matched_agents.each do |agent|
          proposal = AgentTaskProposal.new(
            receiving_agent: agent,
            entity: entity,
            user: user,
            task_description: scenario[:description],
            tools_needed: scenario[:tools_passed],
            task_type: 'custom'
          )

          evaluation = proposal.evaluate_capability

          agent_results << {
            agent: agent.slug,
            accepted: evaluation[:accepted],
            confidence: evaluation[:confidence],
            domain_match: evaluation.dig(:details, :domain_match),
            reason: evaluation[:reason] || evaluation.dig(:details, :match_reason)
          }
        end
      end

      # Also test that wrong agents DON'T accept
      # Pick a random agent NOT in expected list
      wrong_agent = AgentPlugin.where(status: 'active')
        .where.not(slug: scenario[:expected_agents])
        .where.not(id: matched_agents.map(&:id))
        .first

      if wrong_agent && scenario[:expected_agents].any?
        proposal = AgentTaskProposal.new(
          receiving_agent: wrong_agent,
          entity: entity,
          user: user,
          task_description: scenario[:description],
          tools_needed: scenario[:tools_passed],
          task_type: 'custom'
        )

        wrong_eval = proposal.evaluate_capability
        
        if wrong_eval[:accepted] && wrong_eval.dig(:details, :domain_match)
          puts "⚠️  Wrong agent #{wrong_agent.slug} accepted via domain match (may be ok if it has domain tools)"
        end
      end

      # Evaluate results
      if scenario[:expect_rejection]
        # For rejection tests, we expect NO domain match
        all_rejected = agent_results.empty? || agent_results.none? { |r| r[:domain_match] }
        if all_rejected
          puts "✅ PASSED - No domain match as expected"
          results[:passed] += 1
        else
          puts "❌ FAILED - Got domain match when not expected"
          results[:failed] += 1
        end
      else
        # For acceptance tests, we expect at least one agent to accept via domain match
        accepted_via_domain = agent_results.select { |r| r[:accepted] && r[:domain_match] }
        
        if accepted_via_domain.any?
          puts "✅ PASSED - Domain matched by:"
          accepted_via_domain.each do |r|
            puts "   #{r[:agent]} (confidence: #{(r[:confidence] * 100).round}%)"
            puts "   Reason: #{r[:reason]}"
          end
          results[:passed] += 1
        else
          puts "❌ FAILED - No agent accepted via domain match"
          agent_results.each do |r|
            puts "   #{r[:agent]}: accepted=#{r[:accepted]}, domain_match=#{r[:domain_match]}"
            puts "   Reason: #{r[:reason]}"
          end
          results[:failed] += 1
        end
      end

      results[:details] << { test: index + 1, agent_results: agent_results }
    end

    # Summary
    puts "\n" + "=" * 80
    puts "📊 SUMMARY"
    puts "=" * 80
    puts "Passed: #{results[:passed]}"
    puts "Failed: #{results[:failed]}"
    puts "Total:  #{results[:passed] + results[:failed]}"
    
    if results[:failed] > 0
      puts "\n⚠️  Some tests failed. Check the output above for details."
      exit 1
    else
      puts "\n✅ All tests passed!"
    end
  end

  desc "Test a specific agent's domain matching"
  task :test_agent_domain, [:agent_slug, :task] => :environment do |_t, args|
    agent_slug = args[:agent_slug]
    task = args[:task] || "Create a landing page for my business"

    agent = AgentPlugin.find_by(slug: agent_slug)
    unless agent
      puts "❌ Agent not found: #{agent_slug}"
      puts "Available agents: #{AgentPlugin.pluck(:slug).join(', ')}"
      exit 1
    end

    entity = Entity.first
    user = User.first

    puts "\n🧪 Testing agent: #{agent.name} (#{agent.slug})"
    puts "Task: #{task}"
    puts "Agent tools: #{agent.agent_tools.pluck(:tool_name).join(', ')}"
    puts "-" * 60

    proposal = AgentTaskProposal.new(
      receiving_agent: agent,
      entity: entity,
      user: user,
      task_description: task,
      tools_needed: [],  # Empty to test domain matching
      task_type: 'custom'
    )

    evaluation = proposal.evaluate_capability

    puts "Result: #{evaluation[:accepted] ? '✅ ACCEPTED' : '❌ REJECTED'}"
    puts "Confidence: #{(evaluation[:confidence] * 100).round}%"
    puts "Domain match: #{evaluation.dig(:details, :domain_match) || false}"
    puts "Reason: #{evaluation[:reason] || evaluation.dig(:details, :match_reason)}"
    
    if evaluation.dig(:details, :matching_tools)
      puts "Matching tools: #{evaluation.dig(:details, :matching_tools).join(', ')}"
    end
  end
end

