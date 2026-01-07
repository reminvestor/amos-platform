# frozen_string_literal: true

namespace :amos do
  desc "Show AMOS Orchestrator status and capabilities"
  task :status, [:entity_id] => :environment do |t, args|
    entity = args.entity_id ? Entity.find(args.entity_id) : Entity.first
    raise "No entity found" unless entity

    user = entity.users.first

    puts "\n" + "="*70
    puts "🤖 AMOS ORCHESTRATOR STATUS"
    puts "="*70

    orchestrator = Amos::Orchestrator.new(entity: entity, user: user)

    # Self description
    puts "\n📋 WHO AM I?"
    puts orchestrator.self_description

    # Platform health
    health = orchestrator.platform_health
    puts "\n🏥 PLATFORM HEALTH:"
    puts "  Score:           #{health[:score_percent]}%"
    puts "  Status:          #{health[:status].to_s.humanize}"
    puts "  Active Agents:   #{health[:active_agents]}"
    puts "  Anomalies:       #{health[:anomaly_count]}"

    # Capabilities
    caps = orchestrator.capabilities
    puts "\n🔧 CAPABILITIES:"
    puts "  Direct Tools:    #{caps.direct_capabilities.count}"
    puts "  Agents:          #{orchestrator.available_agents.count}"
    orchestrator.available_agents.each do |agent|
      puts "    - #{agent[:name]}: #{agent[:specializations].first(2).join(', ')}"
    end

    # Tickets
    tickets = orchestrator.ticket_summary
    puts "\n🎫 TICKETS:"
    puts "  Open:            #{tickets[:open]}"
    puts "  Critical:        #{tickets[:critical]}"
    puts "  Pending PRs:     #{tickets[:pending_prs]}"

    puts "\n" + "="*70 + "\n"
  end

  desc "Test AMOS routing for a message"
  task :route, [:message] => :environment do |t, args|
    raise "Usage: rake amos:route['your message here']" unless args.message

    entity = Entity.first
    user = entity.users.first

    puts "\n🤖 AMOS ROUTING TEST"
    puts "="*50

    orchestrator = Amos::Orchestrator.new(entity: entity, user: user)
    decision = orchestrator.route(args.message)

    puts "\n📝 Message: \"#{args.message}\""
    puts "\n📊 Routing Decision:"
    puts "  Action:          #{decision[:action]}"
    puts "  Category:        #{decision[:category]}"
    puts "  Confidence:      #{(decision[:confidence] * 100).round}%"
    puts "  Reason:          #{decision[:reason]}"

    if decision[:agent]
      puts "\n🤝 Delegating to: #{decision[:agent][:name]}"
    end

    if decision[:tool]
      puts "\n🔧 Using tool: #{decision[:tool]}"
    end

    if decision[:limitation]
      puts "\n⚠️ Limitation: #{decision[:limitation][:capability]}"
      puts "   Alternative: #{decision[:limitation][:alternative]}"
    end

    puts "\n💬 AMOS would say:"
    puts "  \"#{orchestrator.explain_routing(args.message)}\""

    if decision[:routing_context].present?
      puts "\n📋 Routing Context for Prompt:"
      puts decision[:routing_context].lines.map { |l| "  #{l}" }.join
    end

    puts "\n" + "="*50 + "\n"
  end

  desc "Generate AMOS system prompt"
  task :prompt, [:entity_id] => :environment do |t, args|
    entity = args.entity_id ? Entity.find(args.entity_id) : Entity.first
    user = entity.users.first

    orchestrator = Amos::Orchestrator.new(entity: entity, user: user)
    prompt = orchestrator.system_prompt

    puts "\n🤖 AMOS SYSTEM PROMPT"
    puts "="*70
    puts prompt
    puts "="*70
    puts "\nTotal length: #{prompt.length} characters"
  end

  desc "Show AMOS capabilities"
  task :capabilities, [:entity_id] => :environment do |t, args|
    entity = args.entity_id ? Entity.find(args.entity_id) : Entity.first

    caps = Amos::CapabilityRegistry.new(entity)

    puts "\n🔧 AMOS CAPABILITIES"
    puts "="*70

    puts "\n📋 DIRECT CAPABILITIES (AMOS can do these with tools):"
    caps.direct_capabilities.each do |key, cap|
      puts "\n  #{cap[:name]} (#{key})"
      puts "    #{cap[:description]}"
      puts "    Category: #{cap[:category]}"
      puts "    Examples: #{cap[:examples].first(2).join(', ')}"
    end

    puts "\n\n🤝 AGENT CAPABILITIES (AMOS delegates these):"
    caps.available_agents.each do |agent|
      puts "\n  #{agent[:name]} (#{agent[:slug]})"
      puts "    Specializations: #{agent[:specializations].join(', ')}"
    end

    puts "\n\n⚠️ LIMITATIONS (AMOS cannot do these):"
    caps.limitations.each do |limit|
      puts "\n  #{limit[:capability]}"
      puts "    Status: #{limit[:status]}"
      puts "    Alternative: #{limit[:alternative]}"
    end

    puts "\n" + "="*70 + "\n"
  end

  desc "Interactive AMOS routing test"
  task :interactive => :environment do
    entity = Entity.first
    user = entity.users.first

    orchestrator = Amos::Orchestrator.new(entity: entity, user: user)

    puts "\n🤖 AMOS INTERACTIVE ROUTING TEST"
    puts "="*50
    puts "Type messages to see how AMOS would route them."
    puts "Type 'quit' to exit.\n\n"

    loop do
      print "You: "
      message = STDIN.gets&.strip

      break if message.nil? || message.downcase == 'quit'
      next if message.empty?

      decision = orchestrator.route(message)

      puts "\n🤖 AMOS:"
      puts "   Action: #{decision[:action]} (#{(decision[:confidence] * 100).round}% confidence)"
      puts "   \"#{orchestrator.explain_routing(message)}\""

      if decision[:agent]
        puts "   → Delegating to: #{decision[:agent][:name]}"
      end

      puts ""
    end

    puts "\nGoodbye! 👋\n"
  end

  desc "Demo AMOS orchestration with sample messages"
  task :demo => :environment do
    entity = Entity.first
    user = entity.users.first

    orchestrator = Amos::Orchestrator.new(entity: entity, user: user)

    sample_messages = [
      "What is our refund policy?",
      "Send an email to john@example.com about the proposal",
      "Create a marketing campaign for our new product",
      "Analyze our sales data for last quarter",
      "The email feature is not working, I'm getting an error",
      "Delete all customer data",
      "Generate a video for our landing page",
      "What can you do?"
    ]

    puts "\n🤖 AMOS ORCHESTRATION DEMO"
    puts "="*70

    sample_messages.each do |message|
      decision = orchestrator.route(message)

      puts "\n📝 \"#{message}\""
      puts "   → #{decision[:action].to_s.humanize}"
      puts "   → \"#{orchestrator.explain_routing(message)}\""

      case decision[:action]
      when :delegate_to_agent
        puts "   → Agent: #{decision[:agent][:name]}"
      when :use_tool
        puts "   → Tool: #{decision[:tool]}"
      when :decline_gracefully
        puts "   → Alternative: #{decision[:limitation][:alternative]}"
      end
    end

    puts "\n" + "="*70 + "\n"
  end
end


