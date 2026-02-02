# frozen_string_literal: true

# SkillLibraryService - Dynamic skill/expertise injection for AMOS
#
# This extends the GuidanceLibrary concept to support:
# 1. User-uploaded SKILL.md files (Claude format)
# 2. Integration-specific skills (Stripe, QuickBooks, etc.)
# 3. Semantic discovery (find relevant skills based on message)
#
# Philosophy:
# - Skills are NOT agents - they're expertise that AMOS uses directly
# - Skills are like "how-to guides" that get injected into context
# - Tools are what you DO, Skills are HOW you do it
#
# Usage:
#   skill = SkillLibraryService.discover_skill(
#     message: "Get the last 10 charges from Stripe",
#     entity: entity,
#     integrations: ["stripe"]
#   )
#   # Returns skill content to inject into AMOS's prompt
#
class SkillLibraryService
  # ═══════════════════════════════════════════════════════════════
  # SKILL DISCOVERY
  # ═══════════════════════════════════════════════════════════════

  # Discover relevant skills for a message
  # Returns: { skill_block: String, source: String, skill_names: Array }
  def self.discover_skills(message:, entity: nil, integrations: [], canvas_context: nil, limit: 3)
    skills_found = []
    
    # Priority 1: Integration-specific skills (if integrations mentioned)
    if integrations.any?
      integrations.each do |integration_name|
        skill = get_integration_skill(integration_name)
        skills_found << skill if skill
      end
    end
    
    # Priority 2: Canvas-based skills (if on a specific canvas)
    if canvas_context.present?
      canvas_skill = get_canvas_skill(canvas_context)
      skills_found << canvas_skill if canvas_skill
    end
    
    # Priority 3: Keyword-based skills from message
    keyword_skills = detect_skills_from_message(message)
    skills_found.concat(keyword_skills)
    
    # Priority 4: Entity's custom uploaded skills (semantic search)
    if entity.present?
      custom_skills = search_custom_skills(message: message, entity: entity, limit: limit)
      skills_found.concat(custom_skills)
    end
    
    # Deduplicate and limit
    skills_found = skills_found.uniq { |s| s[:name] }.first(limit)
    
    return nil if skills_found.empty?
    
    # Build combined skill block
    skill_block = build_skill_block(skills_found)
    skill_names = skills_found.map { |s| s[:name] }
    
    Rails.logger.info "📚 [SkillLibrary] Injecting #{skills_found.size} skills: #{skill_names.join(', ')}"
    
    {
      skill_block: skill_block,
      skill_names: skill_names,
      skills: skills_found,
      source: skills_found.map { |s| s[:source] }.uniq.join(', ')
    }
  end

  # ═══════════════════════════════════════════════════════════════
  # INTEGRATION SKILLS
  # Pre-defined skills for common integrations
  # ═══════════════════════════════════════════════════════════════

  INTEGRATION_SKILLS = {
    'stripe' => {
      name: 'Stripe API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Stripe Integration Skill
        
        ### Key Patterns
        - All amounts are in CENTS (divide by 100 for display)
        - Use `limit` parameter (max 100) for list operations
        - Use `starting_after` for pagination (cursor-based)
        - Date filters use `created[gte]` and `created[lte]` (Unix timestamps)
        
        ### Common Operations
        - `list_charges` - Get payment history
        - `list_customers` - Get customer list
        - `list_subscriptions` - Active subscriptions
        - `list_invoices` - Invoice history
        - `retrieve_balance` - Current balance
        
        ### DO NOT USE these parameters (they don't exist):
        ❌ `order`, `sort`, `sort_by`, `direction` - Stripe doesn't support sorting
        ❌ `status` on charges - Use `paid` boolean filter instead
        
        ### Example: Get recent charges
        ```
        execute_integration_action(
          integration: "stripe",
          action: "list_charges",
          inputs: { limit: 10 }
        )
        ```
        
        ### Currency Display
        Stripe returns amounts in cents. When displaying:
        - $699 charge → shows as 69900 in API → display as $699.00
      SKILL
    },

    'quickbooks' => {
      name: 'QuickBooks API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## QuickBooks Integration Skill
        
        ### Query Language
        QuickBooks uses SQL-like queries, NOT REST parameters:
        
        ```
        execute_integration_action(
          integration: "quickbooks",
          action: "query",
          inputs: { query: "SELECT * FROM Invoice WHERE Balance > '0'" }
        )
        ```
        
        ### Query Examples
        - Open invoices: `SELECT * FROM Invoice WHERE Balance > '0'`
        - Recent customers: `SELECT * FROM Customer ORDERBY MetaData.CreateTime DESC MAXRESULTS 10`
        - Specific customer: `SELECT * FROM Customer WHERE DisplayName LIKE '%Smith%'`
        
        ### Common Entities
        - `Invoice` - Customer invoices
        - `Customer` - Customer records
        - `Payment` - Payment records
        - `Bill` - Vendor bills
        - `Vendor` - Vendor records
        
        ### DO NOT USE:
        ❌ `Status` field on invoices - Use `Balance > '0'` for unpaid
        ❌ REST-style filters - Use SQL queries instead
        
        ### Date Filtering
        Use: `WHERE TxnDate > '2024-01-01'`
      SKILL
    },

    'hubspot' => {
      name: 'HubSpot API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## HubSpot Integration Skill
        
        ### Key Concepts
        - Objects: contacts, companies, deals, tickets
        - Properties define custom fields
        - Associations link objects together
        
        ### Common Operations
        - `list_contacts` - Get contact list
        - `create_contact` - Create new contact
        - `list_deals` - Get deal pipeline
        - `create_deal` - Create new deal
        
        ### Required Fields
        - Contacts: `email` (required), `firstname`, `lastname`
        - Deals: `dealname` (required), `amount`, `dealstage`
        
        ### Pagination
        Use `after` cursor for pagination, not `offset`.
      SKILL
    },

    'mailgun' => {
      name: 'Mailgun API Expert',
      source: 'built-in',
      content: <<~SKILL.strip
        ## Mailgun Integration Skill
        
        ### Sending Email
        ```
        execute_integration_action(
          integration: "mailgun",
          action: "send_email",
          inputs: {
            from: "sender@domain.com",
            to: "recipient@example.com",
            subject: "Subject line",
            html: "<p>HTML content</p>"
          }
        )
        ```
        
        ### Required: Verified Domain
        The `from` address must use a verified domain.
        
        ### Tracking
        - Opens and clicks tracked automatically
        - Use `o:tracking` to disable
      SKILL
    }
  }.freeze

  # ═══════════════════════════════════════════════════════════════
  # TASK-BASED SKILLS
  # Specialized skills for common task patterns
  # ═══════════════════════════════════════════════════════════════

  TASK_SKILLS = {
    'tdd' => {
      name: 'Test-Driven Development',
      keywords: %w[test tdd testing spec unit integration],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Test-Driven Development Skill
        
        ### The TDD Cycle (MANDATORY)
        1. RED: Write failing test first
        2. GREEN: Write minimal code to pass
        3. REFACTOR: Clean up while tests pass
        
        ### Rails Testing Commands
        ```bash
        docker-compose run --rm web rails test path/to/test.rb
        ```
        
        ### Key Rules
        - Test MUST fail before writing implementation
        - Write MINIMUM code to pass
        - Refactor only with green tests
      SKILL
    },

    'debugging' => {
      name: 'Systematic Debugging',
      keywords: %w[debug error bug fix broken failing crash exception],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Debugging Skill
        
        ### Systematic Approach
        1. REPRODUCE: Confirm the exact error
        2. ISOLATE: Find the smallest failing case
        3. HYPOTHESIZE: Form theory about cause
        4. TEST: Verify hypothesis with targeted check
        5. FIX: Make minimal change
        6. VERIFY: Confirm fix doesn't break other things
        
        ### Common Rails Debugging
        - Check logs: `docker-compose logs -f web`
        - Rails console: `docker-compose exec web rails c`
        - Database: `docker-compose exec web rails dbconsole`
      SKILL
    },

    'data_analysis' => {
      name: 'Data Analysis',
      keywords: %w[analyze data chart graph report metrics statistics],
      source: 'built-in',
      content: <<~SKILL.strip
        ## Data Analysis Skill
        
        ### Approach
        1. UNDERSTAND: What question are we answering?
        2. GATHER: Collect relevant data
        3. CLEAN: Handle missing/invalid values
        4. ANALYZE: Apply appropriate methods
        5. VISUALIZE: Present findings clearly
        
        ### Best Practices
        - State assumptions explicitly
        - Show sample data before full analysis
        - Explain statistical methods used
        - Provide actionable insights
      SKILL
    }
  }.freeze

  # ═══════════════════════════════════════════════════════════════
  # PRIVATE METHODS
  # ═══════════════════════════════════════════════════════════════

  private_class_method def self.get_integration_skill(integration_name)
    skill_data = INTEGRATION_SKILLS[integration_name.to_s.downcase]
    return nil unless skill_data
    
    {
      name: skill_data[:name],
      content: skill_data[:content],
      source: skill_data[:source],
      type: :integration,
      integration: integration_name
    }
  end

  private_class_method def self.get_canvas_skill(canvas_context)
    # Canvas-specific skills are handled by GuidanceLibrary
    # This is a hook for future canvas-specific skill additions
    nil
  end

  private_class_method def self.detect_skills_from_message(message)
    return [] if message.blank?
    
    msg_lower = message.downcase
    skills = []
    
    TASK_SKILLS.each do |_key, skill_data|
      # Check if any keywords match
      if skill_data[:keywords].any? { |kw| msg_lower.include?(kw) }
        skills << {
          name: skill_data[:name],
          content: skill_data[:content],
          source: skill_data[:source],
          type: :task
        }
      end
    end
    
    skills
  end

  private_class_method def self.search_custom_skills(message:, entity:, limit:)
    # Search entity's custom uploaded skills (from AgentPlugin with skill_format)
    # These are skills imported via SkillFileImporterService
    
    custom_skills = AgentPlugin.where(entity: entity)
                               .where("configuration->>'skill_format' = ?", 'claude_skill_md')
                               .limit(limit)
    
    return [] if custom_skills.empty?
    
    # Simple keyword matching for now (could use vector search later)
    msg_words = message.downcase.split(/\W+/).reject { |w| w.length < 3 }
    
    custom_skills.filter_map do |plugin|
      # Check if skill is relevant to message
      skill_text = "#{plugin.name} #{plugin.description}".downcase
      relevance = msg_words.count { |w| skill_text.include?(w) }
      
      next nil if relevance == 0
      
      prompt_text = plugin.system_prompt.is_a?(Hash) ? 
                    plugin.system_prompt['prompt'] : 
                    plugin.system_prompt.to_s
      
      {
        name: plugin.name,
        content: prompt_text,
        source: 'custom',
        type: :custom,
        plugin_id: plugin.id,
        relevance: relevance
      }
    end.sort_by { |s| -s[:relevance] }
  end

  private_class_method def self.build_skill_block(skills)
    return nil if skills.empty?
    
    blocks = skills.map do |skill|
      <<~BLOCK
        ### 📚 #{skill[:name]}
        #{skill[:content]}
      BLOCK
    end
    
    <<~COMBINED
      ## 🎓 RELEVANT SKILLS
      
      The following expertise has been loaded to help with this task:
      
      #{blocks.join("\n---\n\n")}
    COMBINED
  end
end
