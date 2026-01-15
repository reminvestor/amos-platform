# frozen_string_literal: true

# AgentTrainingService
#
# Handles the initial training and onboarding of new agents.
# Agents start in 'draft' status and go through training before becoming 'active'.
#
# Training Phases:
# 1. RESEARCH: Web search for API docs, best practices, industry knowledge
# 2. KNOWLEDGE_BUILDING: Load docs into agent's RAG store
# 3. DOMAIN_LEARNING: Add domain principles (e.g., accounting basics for QuickBooks agent)
# 4. COMPETENCY_TESTING: Verify agent can handle common scenarios
#
# Usage:
#   service = AgentTrainingService.new(agent)
#   service.start_training!
#   # Or run specific phases:
#   service.research_phase!
#   service.knowledge_building_phase!
#   service.domain_learning_phase!
#   service.competency_test_phase!
#   service.graduate_if_ready!
#
class AgentTrainingService
  TRAINING_PHASES = %w[research knowledge_building operation_learning api_doc_research domain_learning competency_testing].freeze
  
  # Domain knowledge topics by agent type
  DOMAIN_KNOWLEDGE = {
    'quickbooks' => {
      integration: 'quickbooks',
      topics: [
        'QuickBooks API documentation',
        'QuickBooks Query Language syntax',
        'Double-entry accounting basics',
        'Invoice lifecycle management',
        'Accounts receivable best practices'
      ],
      principles: [
        {
          title: 'Double-Entry Accounting Basics',
          content: <<~CONTENT
            # Double-Entry Accounting Fundamentals
            
            Every transaction affects at least two accounts:
            - Debits increase assets and expenses
            - Credits increase liabilities, equity, and revenue
            - Total debits must equal total credits
            
            ## Common Account Types
            - **Assets**: Cash, Accounts Receivable, Inventory
            - **Liabilities**: Accounts Payable, Loans, Unearned Revenue
            - **Equity**: Owner's Equity, Retained Earnings
            - **Revenue**: Sales, Service Income
            - **Expenses**: Rent, Utilities, Salaries
            
            ## Invoice Lifecycle
            1. Invoice Created → Increases Accounts Receivable
            2. Payment Received → Decreases A/R, Increases Cash
            3. Invoice Voided → Reverses the original entry
            
            ## Best Practices
            - Always verify customer exists before creating invoice
            - Use memo fields for context
            - Reconcile accounts regularly
          CONTENT
        },
        {
          title: 'QuickBooks Query Language Mastery',
          content: <<~CONTENT
            # QuickBooks Query Language (QBL) Reference
            
            ## Syntax
            SELECT * FROM EntityName WHERE condition ORDERBY field STARTPOSITION n MAXRESULTS m
            
            ## Key Entities (case-sensitive)
            Invoice, Customer, Item, Account, Payment, Vendor, Bill, Estimate
            
            ## Common Patterns
            
            ### Filtering by Status
            - Open invoices: WHERE Balance > '0'
            - Paid invoices: WHERE Balance = '0'
            - Overdue: WHERE Balance > '0' AND DueDate < 'YYYY-MM-DD'
            
            ### Date Filtering
            - After date: WHERE TxnDate >= '2024-01-01'
            - Date range: WHERE TxnDate >= '2024-01-01' AND TxnDate <= '2024-12-31'
            
            ### Text Filtering
            - Partial match: WHERE DisplayName LIKE '%Smith%'
            - Exact match: WHERE DisplayName = 'John Smith'
            
            ### Pagination
            - First 50: MAXRESULTS 50
            - Next 50: STARTPOSITION 51 MAXRESULTS 50
            
            ## Important Notes
            - Values must be in single quotes
            - Entity names are case-sensitive
            - No JOIN operations (denormalized data model)
            - Use numeric IDs for references (CustomerRef = '123')
          CONTENT
        }
      ]
    },
    'stripe' => {
      integration: 'stripe',
      topics: [
        'Stripe API documentation',
        'Payment processing best practices',
        'Subscription management patterns',
        'PCI compliance basics',
        'Stripe webhook handling'
      ],
      principles: [
        {
          title: 'Payment Processing Fundamentals',
          content: <<~CONTENT
            # Payment Processing with Stripe
            
            ## Payment Flow
            1. Customer provides payment method
            2. PaymentIntent created (captures intent to collect)
            3. Payment method attached
            4. Confirmation triggers actual charge
            5. Webhook confirms completion
            
            ## Key Objects
            - **Customer**: Represents a user, stores payment methods
            - **PaymentMethod**: Card, bank account, or other payment source
            - **PaymentIntent**: Represents a payment lifecycle
            - **Charge**: The actual money movement (deprecated in favor of PI)
            - **Invoice**: For recurring billing
            - **Subscription**: Recurring payment schedule
            
            ## Status Values
            - PaymentIntent: requires_payment_method → requires_confirmation → succeeded
            - Invoice: draft → open → paid | uncollectible | void
            - Subscription: trialing → active → past_due → canceled
            
            ## Best Practices
            - Always use PaymentIntents (not Charges) for new integrations
            - Handle webhooks for reliable status updates
            - Store customer IDs, not card numbers
            - Use idempotency keys for retries
          CONTENT
        },
        {
          title: 'Stripe API Patterns',
          content: <<~CONTENT
            # Stripe API Reference
            
            ## Pagination
            Cursor-based with `starting_after` and `ending_before`
            
            ```
            GET /v1/customers?limit=10&starting_after=cus_xxx
            ```
            
            ## Date Filtering
            Unix timestamps with nested parameters:
            - created[gte]: Created at or after timestamp
            - created[lte]: Created at or before timestamp
            
            ```
            GET /v1/customers?created[gte]=1704067200
            ```
            
            ## Idempotency
            Use Idempotency-Key header for safe retries:
            ```
            POST /v1/customers
            Idempotency-Key: unique-request-id-123
            ```
            
            ## Rate Limits
            - Default: 100 requests/second (test: 25/sec)
            - Use webhooks instead of polling
            
            ## Error Handling
            - 4xx: Client error (fix request)
            - 429: Rate limited (backoff and retry)
            - 5xx: Server error (retry with backoff)
          CONTENT
        }
      ]
    },
    'gmail' => {
      integration: 'gmail',
      topics: [
        'Gmail API documentation',
        'Email formatting best practices',
        'Label management',
        'Email deliverability',
        'MIME message structure'
      ],
      principles: [
        {
          title: 'Email Best Practices',
          content: <<~CONTENT
            # Professional Email Guidelines
            
            ## Subject Lines
            - Be specific and concise (50 chars max)
            - Include action items or deadlines
            - Avoid spam trigger words (FREE, URGENT, !!!)
            
            ## Email Body
            - Start with context/purpose
            - Use bullet points for multiple items
            - Clear call-to-action
            - Professional signature
            
            ## Timing
            - Best open rates: Tuesday-Thursday, 10am-2pm
            - Avoid Mondays and Fridays
            - Consider recipient's timezone
            
            ## Deliverability
            - Authenticate domain (SPF, DKIM, DMARC)
            - Maintain clean list (remove bounces)
            - Monitor spam complaints
          CONTENT
        }
      ]
    }
  }.freeze

  attr_reader :agent, :training_log, :current_phase

  def initialize(agent)
    @agent = agent
    @training_log = []
    @current_phase = nil
  end

  # Start the full training pipeline
  def start_training!
    log_event("🎓 Starting training for agent: #{agent.name}")
    
    # Update agent status to in_school
    agent.update!(status: 'in_school')
    
    # Create enrollment record
    enrollment = create_enrollment
    
    # Run all training phases
    TRAINING_PHASES.each do |phase|
      @current_phase = phase
      log_event("📚 Starting phase: #{phase}")
      
      begin
        send("#{phase}_phase!")
        log_event("✅ Completed phase: #{phase}")
      rescue => e
        log_event("❌ Failed phase #{phase}: #{e.message}")
        enrollment.update!(
          status: 'retry',
          notes: "Failed at #{phase}: #{e.message}"
        )
        return { success: false, phase: phase, error: e.message }
      end
    end
    
    # Graduate the agent
    graduate_if_ready!(enrollment)
  end

  # Phase 1: Research - Web search for relevant information
  def research_phase!
    domain_config = detect_domain_config
    return log_event("⏭️ No domain config found, skipping research") unless domain_config
    
    topics = domain_config[:topics] || []
    log_event("🔍 Researching #{topics.size} topics for #{domain_config[:integration]}")
    
    topics.each do |topic|
      begin
        # Use web search to gather information
        results = perform_web_search(topic)
        
        if results.any?
          # Store research results in agent's knowledge base
          content = format_research_results(topic, results)
          agent.add_to_knowledge(
            content: content,
            title: "Research: #{topic}",
            source: 'web_research',
            metadata: { phase: 'research', topic: topic }
          )
          log_event("  📄 Added research: #{topic}")
        end
      rescue => e
        log_event("  ⚠️ Research failed for #{topic}: #{e.message}")
      end
    end
  end

  # Phase 2: Knowledge Building - Load integration docs into RAG
  def knowledge_building_phase!
    domain_config = detect_domain_config
    return log_event("⏭️ No domain config, skipping knowledge building") unless domain_config
    
    integration_name = domain_config[:integration]
    log_event("📚 Loading integration documentation for #{integration_name}")
    
    # Load the integration-specific documentation
    docs_path = Rails.root.join('docs', 'integrations', "#{integration_name}.md")
    
    if File.exist?(docs_path)
      content = File.read(docs_path)
      agent.add_to_knowledge(
        content: content,
        title: "#{integration_name.titleize} Integration Documentation",
        source: docs_path.to_s,
        metadata: { phase: 'knowledge_building', type: 'integration_docs' }
      )
      log_event("  ✅ Loaded integration documentation")
    else
      log_event("  ⚠️ No integration docs found at #{docs_path}")
    end
    
    # Also add the integration's operation schemas from the database
    add_operation_knowledge(integration_name)
  end

  # Phase 3: Operation Learning - Learn from actual operations and past call results
  def operation_learning_phase!
    domain_config = detect_domain_config
    return log_event("⏭️ No domain config, skipping operation learning") unless domain_config
    
    integration_name = domain_config[:integration]
    integration = Integration.find_by(slug: integration_name)
    return log_event("⚠️ Integration not found: #{integration_name}") unless integration
    
    log_event("🔧 Learning from operations and call history for #{integration_name}")
    
    # Learn from operation definitions - detailed parameter analysis
    learn_from_operations(integration)
    
    # Learn from successful API call results (if any exist)
    learn_from_call_history(integration)
    
    # Learn from real-world usage patterns via web search
    learn_real_world_patterns(integration_name)
  end

  # Phase 4: API Documentation Research - Fetch official docs
  def api_doc_research_phase!
    domain_config = detect_domain_config
    return log_event("⏭️ No domain config, skipping API doc research") unless domain_config
    
    integration_name = domain_config[:integration]
    log_event("📖 Researching official API documentation for #{integration_name}")
    
    # Search for official API documentation
    doc_queries = [
      "#{integration_name} API documentation official",
      "#{integration_name} API reference guide",
      "#{integration_name} API best practices",
      "#{integration_name} API common errors solutions"
    ]
    
    doc_queries.each do |query|
      begin
        results = perform_web_search(query)
        
        if results.any?
          content = format_api_doc_research(query, results)
          agent.add_to_knowledge(
            content: content,
            title: "API Docs: #{query.gsub(integration_name, '').strip.titleize}",
            source: 'api_doc_research',
            metadata: { phase: 'api_doc_research', query: query }
          )
          log_event("  📄 Added: #{query.truncate(40)}")
        end
      rescue => e
        log_event("  ⚠️ API doc research failed: #{e.message}")
      end
    end
  end

  # Phase 5: Domain Learning - Add foundational domain knowledge
  def domain_learning_phase!
    domain_config = detect_domain_config
    return log_event("⏭️ No domain config, skipping domain learning") unless domain_config
    
    principles = domain_config[:principles] || []
    log_event("📖 Teaching #{principles.size} domain principles")
    
    principles.each do |principle|
      agent.add_to_knowledge(
        content: principle[:content],
        title: principle[:title],
        source: 'domain_training',
        metadata: { phase: 'domain_learning', type: 'principle' }
      )
      log_event("  📚 Taught: #{principle[:title]}")
    end
  end

  # Phase 4: Competency Testing - Verify agent can handle scenarios
  def competency_test_phase!
    domain_config = detect_domain_config
    integration_name = domain_config&.dig(:integration)
    
    log_event("🧪 Running competency tests")
    
    test_scenarios = build_test_scenarios(integration_name)
    results = []
    
    test_scenarios.each do |scenario|
      result = run_competency_test(scenario)
      results << result
      
      status = result[:passed] ? "✅" : "❌"
      log_event("  #{status} #{scenario[:name]}: #{result[:summary]}")
    end
    
    passed = results.count { |r| r[:passed] }
    total = results.size
    pass_rate = total > 0 ? (passed.to_f / total * 100).round(1) : 0
    
    log_event("📊 Competency: #{passed}/#{total} tests passed (#{pass_rate}%)")
    
    # Store test results
    agent.update!(
      metadata: agent.metadata.merge(
        'training_competency' => {
          'tests_passed' => passed,
          'tests_total' => total,
          'pass_rate' => pass_rate,
          'tested_at' => Time.current.iso8601
        }
      )
    )
    
    { passed: passed, total: total, pass_rate: pass_rate }
  end

  # Graduate the agent if they pass competency requirements
  def graduate_if_ready!(enrollment = nil)
    competency = agent.metadata.dig('training_competency')
    pass_rate = competency&.dig('pass_rate') || 0
    
    if pass_rate >= 70
      agent.update!(status: 'active')
      enrollment&.graduate!({ pass_rate: pass_rate })
      log_event("🎓 Agent graduated! Pass rate: #{pass_rate}%")
      
      { success: true, status: 'graduated', pass_rate: pass_rate }
    elsif pass_rate >= 50
      agent.update!(status: 'probation')
      enrollment&.probation!({ pass_rate: pass_rate }, "Needs improvement")
      log_event("⚠️ Agent on probation. Pass rate: #{pass_rate}%")
      
      { success: true, status: 'probation', pass_rate: pass_rate }
    else
      log_event("❌ Agent needs more training. Pass rate: #{pass_rate}%")
      
      { success: false, status: 'in_school', pass_rate: pass_rate }
    end
  end

  private

  def create_enrollment
    AgentSchoolEnrollment.create!(
      agent_plugin: agent,
      entity: agent.entity,
      status: 'enrolled',
      enrollment_reason: 'manual',
      attempt_number: 1
    )
  end

  def detect_domain_config
    # Detect domain based on agent name, description, or associated integration
    slug = agent.slug.to_s.downcase
    name = agent.name.to_s.downcase
    description = agent.description.to_s.downcase
    
    DOMAIN_KNOWLEDGE.each do |domain, config|
      if slug.include?(domain) || name.include?(domain) || description.include?(domain)
        return config.merge(domain: domain)
      end
    end
    
    # Check for integration association
    if agent.respond_to?(:integration) && agent.integration.present?
      integration_slug = agent.integration.slug.to_s.downcase
      return DOMAIN_KNOWLEDGE[integration_slug]&.merge(domain: integration_slug)
    end
    
    nil
  end

  def perform_web_search(query)
    return [] unless defined?(Tools::WebSearchTool)
    
    tool = Tools::WebSearchTool.new(
      user: agent.user,
      entity: agent.entity,
      context: {}
    )
    
    result = tool.execute({
      'query' => query,
      'num_results' => 5
    })
    
    result[:results] || result['results'] || []
  rescue => e
    Rails.logger.warn "[AgentTraining] Web search failed: #{e.message}"
    []
  end

  def format_research_results(topic, results)
    content = "# Research: #{topic}\n\n"
    content += "Research conducted: #{Time.current.strftime('%Y-%m-%d')}\n\n"
    
    results.each_with_index do |result, i|
      content += "## Source #{i + 1}: #{result['title'] || result[:title]}\n"
      content += "URL: #{result['url'] || result[:url]}\n"
      content += "#{result['snippet'] || result[:snippet]}\n\n"
    end
    
    content
  end

  def add_operation_knowledge(integration_name)
    integration = Integration.find_by(slug: integration_name)
    return unless integration
    
    operations = integration.integration_operations.active
    return if operations.empty?
    
    content = "# #{integration.name} Available Operations\n\n"
    
    operations.each do |op|
      content += "## #{op.name}\n"
      content += "- **Operation ID**: #{op.operation_id}\n"
      content += "- **Method**: #{op.http_method}\n"
      content += "- **Path**: #{op.path_template}\n"
      content += "- **Description**: #{op.description}\n"
      
      if op.request_schema.present?
        content += "- **Parameters**: #{op.request_schema.to_json}\n"
      end
      
      content += "\n"
    end
    
    agent.add_to_knowledge(
      content: content,
      title: "#{integration.name} Operations Reference",
      source: 'integration_operations',
      metadata: { phase: 'knowledge_building', type: 'operations' }
    )
    
    log_event("  ✅ Added #{operations.count} operation definitions")
  end

  # Learn detailed patterns from operation definitions
  def learn_from_operations(integration)
    operations = integration.integration_operations.active
    return if operations.empty?
    
    content = "# #{integration.name} Operation Deep Dive\n\n"
    content += "Analyzed: #{Time.current.strftime('%Y-%m-%d')}\n\n"
    
    operations.each do |op|
      content += "## #{op.name} (#{op.operation_id})\n\n"
      
      # Analyze the request schema for patterns
      if op.request_schema.present?
        content += "### Required Parameters\n"
        required = op.request_schema['required'] || []
        if required.any?
          required.each { |r| content += "- `#{r}` - REQUIRED\n" }
        else
          content += "- No required parameters\n"
        end
        
        content += "\n### Parameter Details\n"
        props = op.request_schema['properties'] || {}
        props.each do |param, details|
          content += "- **#{param}** (#{details['type'] || 'any'}): #{details['description'] || 'No description'}\n"
          content += "  - Default: #{details['default']}\n" if details['default']
          content += "  - Enum: #{details['enum'].join(', ')}\n" if details['enum']
        end
      end
      
      # Note important patterns
      content += "\n### Usage Notes\n"
      if op.path_template&.include?('/query')
        content += "- ⚠️ This is a QUERY operation - uses SQL-like syntax\n"
        content += "- Must pass `query` parameter with SELECT statement\n"
      end
      
      if op.requires_confirmation
        content += "- ⚠️ Requires user confirmation before execution\n"
      end
      
      content += "\n"
    end
    
    agent.add_to_knowledge(
      content: content,
      title: "#{integration.name} Operation Patterns",
      source: 'operation_analysis',
      metadata: { phase: 'operation_learning', type: 'patterns' }
    )
    
    log_event("  📊 Analyzed #{operations.count} operations for patterns")
  end

  # Learn from historical API call results
  def learn_from_call_history(integration)
    # Find successful integration calls for this integration
    # This uses IntegrationConnection and its call logs
    connections = IntegrationConnection.where(integration: integration)
                                       .where(status: 'connected')
    
    return log_event("  ⚠️ No connections found to learn from") if connections.empty?
    
    # Look for successful API call logs (if tracked)
    call_examples = []
    
    connections.each do |conn|
      # Check if there are logged API calls
      if conn.respond_to?(:api_call_logs) && conn.api_call_logs.any?
        successful_calls = conn.api_call_logs
                               .where(status: 'success')
                               .order(created_at: :desc)
                               .limit(10)
        
        successful_calls.each do |call|
          call_examples << {
            operation: call.operation_id,
            params: call.request_params,
            response_structure: extract_response_structure(call.response_body)
          }
        end
      end
    end
    
    if call_examples.any?
      content = "# #{integration.name} Successful Call Examples\n\n"
      content += "Learned from: #{call_examples.size} successful API calls\n\n"
      
      call_examples.group_by { |c| c[:operation] }.each do |op_id, calls|
        content += "## #{op_id}\n\n"
        content += "### Example Parameters\n"
        calls.first(3).each_with_index do |call, i|
          content += "```json\n#{JSON.pretty_generate(call[:params])}\n```\n\n" if call[:params].present?
        end
        
        if calls.first[:response_structure]
          content += "### Response Structure\n"
          content += "```\n#{calls.first[:response_structure]}\n```\n\n"
        end
      end
      
      agent.add_to_knowledge(
        content: content,
        title: "#{integration.name} Successful Call Patterns",
        source: 'call_history',
        metadata: { phase: 'operation_learning', type: 'call_examples' }
      )
      
      log_event("  ✅ Learned from #{call_examples.size} successful API calls")
    else
      log_event("  ℹ️ No call history available yet")
    end
  end

  # Extract structure from response for learning
  def extract_response_structure(response_body)
    return nil if response_body.blank?
    
    data = response_body.is_a?(String) ? JSON.parse(response_body) : response_body
    extract_structure(data, 0)
  rescue
    nil
  end

  def extract_structure(obj, depth = 0)
    return "..." if depth > 3
    
    case obj
    when Hash
      fields = obj.keys.first(10).map do |k|
        "#{k}: #{extract_structure(obj[k], depth + 1)}"
      end
      "{ #{fields.join(', ')} }"
    when Array
      if obj.first
        "[#{extract_structure(obj.first, depth + 1)}, ...]"
      else
        "[]"
      end
    else
      obj.class.name.downcase
    end
  end

  # Learn from real-world usage patterns
  def learn_real_world_patterns(integration_name)
    queries = [
      "#{integration_name} API integration examples",
      "#{integration_name} API common use cases",
      "#{integration_name} API tutorial"
    ]
    
    queries.each do |query|
      begin
        results = perform_web_search(query)
        
        if results.any?
          content = format_research_results("Real-World: #{query}", results)
          agent.add_to_knowledge(
            content: content,
            title: "Real-World Patterns: #{query.gsub(integration_name, '').strip.titleize}",
            source: 'real_world_research',
            metadata: { phase: 'operation_learning', type: 'real_world' }
          )
          log_event("  🌐 Learned: #{query.truncate(40)}")
        end
      rescue => e
        log_event("  ⚠️ Real-world research failed: #{e.message}")
      end
    end
  end

  def format_api_doc_research(query, results)
    content = "# API Documentation Research: #{query}\n\n"
    content += "Researched: #{Time.current.strftime('%Y-%m-%d')}\n\n"
    
    results.each_with_index do |result, i|
      title = result['title'] || result[:title] || 'Untitled'
      url = result['url'] || result[:url]
      snippet = result['snippet'] || result[:snippet] || ''
      
      content += "## #{i + 1}. #{title}\n"
      content += "Source: #{url}\n\n" if url
      content += "#{snippet}\n\n"
    end
    
    content
  end

  def build_test_scenarios(integration_name)
    base_scenarios = [
      {
        name: "Knowledge Retrieval",
        type: :knowledge_query,
        query: "What are the available operations for this integration?",
        expects_content: true
      }
    ]
    
    case integration_name
    when 'quickbooks'
      base_scenarios + [
        {
          name: "QB Query Syntax",
          type: :knowledge_query,
          query: "How do I list open invoices in QuickBooks?",
          expects_keywords: ['Balance', 'SELECT', 'Invoice']
        },
        {
          name: "QB Date Filtering",
          type: :knowledge_query,
          query: "How do I filter QuickBooks data by date?",
          expects_keywords: ['TxnDate', 'WHERE']
        }
      ]
    when 'stripe'
      base_scenarios + [
        {
          name: "Stripe Pagination",
          type: :knowledge_query,
          query: "How do I paginate Stripe results?",
          expects_keywords: ['starting_after', 'limit']
        },
        {
          name: "Stripe Dates",
          type: :knowledge_query,
          query: "How do I filter Stripe by date?",
          expects_keywords: ['created', 'timestamp', 'gte']
        }
      ]
    else
      base_scenarios
    end
  end

  def run_competency_test(scenario)
    case scenario[:type]
    when :knowledge_query
      results = agent.search_knowledge(scenario[:query], limit: 3)
      
      if scenario[:expects_content]
        passed = results.any?
        summary = passed ? "Found #{results.size} relevant documents" : "No knowledge found"
      elsif scenario[:expects_keywords]
        content = results.map { |r| r[:content] || r['content'] }.join(' ').downcase
        found_keywords = scenario[:expects_keywords].select { |kw| content.include?(kw.downcase) }
        passed = found_keywords.size >= (scenario[:expects_keywords].size * 0.5)
        summary = "Found #{found_keywords.size}/#{scenario[:expects_keywords].size} expected keywords"
      else
        passed = results.any?
        summary = results.any? ? "Knowledge available" : "No results"
      end
      
      { passed: passed, summary: summary, details: results.size }
    else
      { passed: true, summary: "Unknown test type skipped" }
    end
  end

  def log_event(message)
    Rails.logger.info "[AgentTraining] #{message}"
    @training_log << { time: Time.current, message: message }
  end
end

