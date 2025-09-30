# Workflow Template V2: Conversational & Adaptive Architecture

## Executive Summary

After a comprehensive analysis of the current workflow template system, this document proposes **Workflow Template V2** - a conversational, context-aware, and adaptive workflow architecture that aligns with the new conversational UI and WorkflowContext persistence layer.

### Why V2 is Needed

**Current State (V1) Limitations:**
- ❌ Rigid form-based data collection that breaks conversational flow
- ❌ Sequential execution with no adaptation to available context
- ❌ Can't leverage uploaded files, documents, or conversation history
- ❌ Prescriptive tool execution prevents AI from making intelligent choices
- ❌ No integration with the new WorkflowContext system
- ❌ Poor user experience with form-filling interruptions

**V2 Benefits:**
- ✅ Natural conversational data gathering
- ✅ Context-aware execution (uses uploaded files, previous data)
- ✅ Adaptive step execution with intelligent tool selection
- ✅ Seamless WorkflowContext integration
- ✅ Better UX with minimal interruptions
- ✅ Self-healing and resilient execution

---

## System Architecture Deep Dive

### Current System Strengths to Preserve

1. **Multi-Agent Architecture** ⭐
   - Planner, Executor, Verifier, Analyst, Fixer agents work well
   - Clear separation of concerns
   - Adaptive execution already available
   
2. **AI-Powered Variable Extraction** ⭐
   - Smart variable extraction using LLM
   - Universal system (no hardcoded patterns)
   - WorkflowVariable persistence
   
3. **WorkflowContext Persistence** ⭐ (Newly Added)
   - Stores files, user inputs, extracted data
   - Prevents context loss
   - AI-accessible via `get_workflow_context` tool
   
4. **Streaming UI** ⭐
   - Real-time updates via SSE
   - Multiple canvas types (task_progress, interactive_wizard, etc.)
   - Dynamic HTML generation
   
5. **Tool Catalog System** ⭐
   - Role-based tool access
   - Comprehensive tool ecosystem
   - Context-aware execution

### Current Gaps to Address

1. **Template Structure**
   - Too rigid and form-based
   - Doesn't leverage AI decision-making
   - No context awareness built-in

2. **Data Collection**
   - Forces form-based input even when data exists
   - Can't extract from files or conversation
   - No intelligence about what to ask

3. **Step Execution**
   - Prescriptive tool calls
   - Limited adaptability
   - Can't chain tools intelligently

---

## Workflow Template V2 Design

### Core Philosophy

**"Intent-Based, Context-Aware, AI-Driven Execution"**

Instead of prescribing exactly HOW to do something, V2 templates describe WHAT needs to be achieved and let AI agents figure out the best HOW based on available context.

### Template Structure Comparison

#### V1 (Current - Form-Based)
```yaml
steps:
  - id: "collect_info"
    type: "user_input"
    form:
      fields:
        - name: "business_name"
          type: "text"
          required: true
        - name: "industry"
          type: "text"
          required: true
```

**Problems:**
- Forces form display
- Ignores uploaded documents that might contain this info
- Breaks conversational flow
- Can't adapt to partial data

#### V2 (Proposed - Intent-Based)
```yaml
phases:
  - id: "understand_business"
    type: "gather_context"
    intent: "Understand the business, industry, and target audience"
    required_knowledge:
      business_identity:
        - business_name
        - industry
        - value_proposition
      target_market:
        - target_audience
        - customer_pain_points
    context_sources:
      priority:
        - workflow_context  # Check uploaded files first
        - conversation_history
        - entity_profile
        - direct_conversation  # Only ask if missing
    ai_instructions: |
      First check uploaded documents for business info.
      If the user provided a brand guide PDF, extract business details from it.
      Only ask conversationally for information you cannot find in context.
      Be natural - don't ask for things you already know.
```

**Benefits:**
- Checks uploaded files first
- Natural conversation as fallback
- Adaptive to what's available
- Better UX

---

## V2 Template Schema

### Top-Level Structure

```yaml
# Metadata
template_version: 2  # Distinguishes from V1
name: "AI-Powered Landing Page Creation V2"
slug: "landing_page_creation_v2"
description: "Create a professional landing page using conversational AI"
category: "content_generation"

# Template configuration
config:
  execution_mode: "adaptive"  # vs "strict" for V1-style execution
  context_aware: true
  conversational: true
  self_healing: true
  
# Keywords for template matching
keywords:
  - landing page
  - website
  - create page
  - design page

# Phases instead of rigid steps
phases:
  - id: "discovery"
    # Phase definition
  
  - id: "creation"
    # Phase definition
    
  - id: "refinement"
    # Phase definition

# Success criteria
success_criteria:
  - landing_page_created: true
  - contains_hero_section: true
  - contains_cta: true
  - images_processed: true

# Validation rules
validation:
  required_context:
    - business_context
    - design_direction
  quality_checks:
    - check_html_validity
    - check_responsive_design
```

### Phase Definition Schema

```yaml
phases:
  - id: "discovery"
    name: "Understand Requirements"
    type: "gather_context"  # Types: gather_context, execute_goal, validate_result
    
    # What this phase needs to achieve
    goal: "Gather all information needed to create a compelling landing page"
    
    # Required knowledge/data
    required_knowledge:
      business_context:
        - business_name
        - industry
        - value_proposition
        - target_audience
      design_preferences:
        - style_preference
        - color_scheme
        - brand_assets
      content_requirements:
        - main_headline
        - key_features
        - call_to_action
    
    # Where to look for information (priority order)
    context_sources:
      priority:
        - workflow_context      # Uploaded files, stored data
        - conversation_history  # What user said
        - entity_profile        # Known entity data
        - web_search           # External research
        - direct_conversation   # Ask user (last resort)
    
    # How to extract from each source
    extraction_strategies:
      workflow_context:
        file_types:
          - "pdf": "Extract brand guidelines, business info"
          - "image": "Analyze for brand colors, style preferences"
          - "docx": "Extract content, messaging, value props"
      conversation_history:
        look_for:
          - business_description
          - goals_and_objectives
          - audience_mentions
      entity_profile:
        use_fields:
          - entity.name
          - entity.industry
          - entity.subdomain
    
    # AI instructions for this phase
    ai_instructions: |
      You are gathering information for a landing page creation.
      
      PRIORITY 1: Check workflow_context for uploaded files
      - If there's a brand guide PDF, extract business info, colors, fonts
      - If there are images, analyze them for brand style and aesthetics
      - If there's a competitor site reference, analyze its structure
      
      PRIORITY 2: Review conversation history
      - User may have already described their business
      - Look for mentions of audience, goals, value proposition
      
      PRIORITY 3: Check entity profile
      - Use known business name, industry if available
      
      PRIORITY 4: Conversational gathering (ONLY FOR MISSING INFO)
      - Ask naturally in chat, don't show forms
      - Ask related questions together
      - If you have partial info, confirm and ask for gaps
      - Example: "I see from your brand guide that you're in SaaS. 
        Who is your primary target audience?"
      
      Be intelligent:
      - Don't ask for what you already have
      - Infer when possible
      - Confirm assumptions rather than asking from scratch
    
    # Tools this phase can use
    allowed_tools:
      - get_workflow_context
      - web_search
      - analyze_document
      - extract_colors_from_image
      - get_data  # For fetching entity data
    
    # When is this phase complete?
    completion_criteria:
      all_required_knowledge_gathered: true
      or:
        user_approved_partial_data: true
        max_conversation_turns: 3
    
    # What to do if phase fails
    fallback_strategy:
      action: "use_defaults"
      defaults:
        style_preference: "modern"
        color_scheme: "professional"
```

### Execute Goal Phase Type

```yaml
phases:
  - id: "creation"
    name: "Build Landing Page"
    type: "execute_goal"
    
    goal: "Create a professional landing page with the gathered requirements"
    
    # Prerequisites (from previous phases)
    requires_from_previous:
      - business_context
      - design_preferences
      - content_requirements
      - processed_images  # If any were uploaded
    
    # How to achieve the goal (high-level)
    execution_strategy:
      approach: "adaptive"  # Let AI choose tools and approach
      
      # AI can use any of these tools in any order/combination
      allowed_tools:
        - generate_ai_landing_page
        - update_landing_page_content
        - create_object
        - update_object
        - get_workflow_context
      
      # But must meet these constraints
      constraints:
        - must_use_uploaded_images: true
        - must_include_cta: true
        - max_ai_calls: 5
        - budget:
            max_tokens: 10000
            max_cost_usd: 0.50
      
      # Success criteria for this phase
      success_when:
        - landing_page_id_exists: true
        - html_content_generated: true
        - all_required_sections_present: true
    
    # AI instructions
    ai_instructions: |
      Create a landing page using the gathered requirements.
      
      INTELLIGENT EXECUTION:
      1. Check workflow_context for uploaded images - use them!
      2. If brand colors were extracted, use them in design
      3. Use generate_ai_landing_page tool with all context
      4. If generation fails, try update_landing_page_content
      5. Chain tools as needed - you have flexibility
      
      QUALITY STANDARDS:
      - Responsive design (mobile-friendly)
      - Fast loading (optimize images)
      - Accessible (proper HTML structure)
      - Conversion-optimized (clear CTA)
      
      You can make multiple tool calls if needed.
      Be creative and adaptive to achieve the goal.
    
    # Adaptive execution settings
    adaptive:
      enabled: true
      max_attempts: 3
      self_healing: true
      allow_tool_chaining: true
```

### Validate Result Phase Type

```yaml
phases:
  - id: "quality_check"
    name: "Validate & Refine"
    type: "validate_result"
    
    goal: "Ensure the landing page meets quality standards"
    
    # What to validate
    validation_rules:
      - rule: "html_validity"
        check: "Valid HTML5 structure"
        tool: "validate_html"
        
      - rule: "responsive_design"
        check: "Works on mobile, tablet, desktop"
        tool: "check_responsive"
        
      - rule: "has_cta"
        check: "Contains clear call-to-action"
        validation_function: |
          page_content.include?('cta') || 
          page_content.include?('button')
          
      - rule: "images_loaded"
        check: "All images have valid URLs"
        tool: "verify_image_urls"
        
      - rule: "brand_consistent"
        check: "Uses uploaded brand colors/fonts"
        requires_context: ["uploaded_brand_guide"]
    
    # What to do when validation fails
    on_failure:
      action: "attempt_fix"
      max_fix_attempts: 2
      fix_strategy:
        use_fixer_agent: true
        allowed_fixes:
          - add_missing_cta
          - fix_responsive_issues
          - optimize_images
          - adjust_colors_to_brand
    
    # AI instructions for validation
    ai_instructions: |
      Validate the generated landing page against quality criteria.
      
      FOR EACH VALIDATION:
      1. Run the specified check
      2. If it passes, mark as complete
      3. If it fails, use FixerAgent to attempt correction
      
      Be thorough but pragmatic - minor issues can be noted
      for manual review rather than blocking.
```

---

## Implementation Architecture

### Component Interactions

```
User Message + Files
        ↓
[Scout Controller]
        ↓
[InteractiveTaskService] ← Stores files in WorkflowContext
        ↓
[ScoutGenericToolsServiceV2] ← Decides: direct or delegate?
        ↓
[PlannerAgentService] ← Selects template (V1 or V2)
        ↓
[WorkflowEngineV2] ← Executes phases
        ↓
[Phase Executor] ← Different for each phase type
   ├── GatherContextExecutor (for gather_context phases)
   ├── GoalExecutor (for execute_goal phases)  
   └── ValidationExecutor (for validate_result phases)
        ↓
[Tools + WorkflowContext] ← Access data, execute actions
        ↓
[Stream Updates to UI] ← Real-time progress
```

### New Components Needed

#### 1. **PhaseExecutor** (Base Class)
```ruby
module Agents
  class PhaseExecutor
    def initialize(phase, context)
      @phase = phase
      @context = context
      @ai_service = BedrockService.new
    end
    
    def execute
      # Override in subclasses
      raise NotImplementedError
    end
    
    protected
    
    def check_completion_criteria
      # Evaluate phase completion
    end
    
    def store_phase_output(data)
      # Store in WorkflowContext
    end
  end
end
```

#### 2. **GatherContextExecutor**
```ruby
module Agents
  class GatherContextExecutor < PhaseExecutor
    def execute
      # 1. Check context sources in priority order
      gathered_data = {}
      
      @phase[:context_sources][:priority].each do |source|
        case source
        when 'workflow_context'
          gathered_data.merge!(check_workflow_context)
        when 'conversation_history'
          gathered_data.merge!(check_conversation_history)
        when 'entity_profile'
          gathered_data.merge!(check_entity_profile)
        when 'direct_conversation'
          gathered_data.merge!(ask_user_conversationally)
        end
        
        # Stop if we have all required knowledge
        break if has_all_required_knowledge?(gathered_data)
      end
      
      # 2. Store gathered data in WorkflowContext
      store_gathered_knowledge(gathered_data)
      
      # 3. Return result
      {
        success: true,
        data: gathered_data,
        phase: @phase[:id]
      }
    end
    
    private
    
    def check_workflow_context
      # Use get_workflow_context tool
      context_data = ToolCatalog.execute_tool(
        'get_workflow_context',
        { data_type: 'all' },
        @context
      )
      
      # Use AI to extract relevant info
      extract_with_ai(context_data, @phase[:required_knowledge])
    end
    
    def ask_user_conversationally
      # Generate natural question based on missing data
      missing_fields = find_missing_fields
      
      prompt = generate_conversational_prompt(missing_fields)
      
      # Send via progress callback
      @context[:progress_callback]&.call({
        type: 'content_chunk',
        content: prompt,
        awaiting_input: true
      })
      
      # Return awaiting_input status
      { status: 'awaiting_input', prompt: prompt }
    end
  end
end
```

#### 3. **GoalExecutor** (Adaptive)
```ruby
module Agents
  class GoalExecutor < PhaseExecutor
    def execute
      # Use AdaptiveStepExecutor internally but for phase-level goal
      goal = @phase[:goal]
      allowed_tools = @phase.dig(:execution_strategy, :allowed_tools)
      constraints = @phase.dig(:execution_strategy, :constraints)
      
      # Build an adaptive execution plan
      plan = build_adaptive_plan(goal, allowed_tools, constraints)
      
      # Execute with self-healing
      result = execute_with_adaptation(plan)
      
      # Validate success criteria
      if meets_success_criteria?(result)
        {
          success: true,
          data: result,
          phase: @phase[:id]
        }
      else
        {
          success: false,
          error: "Goal not achieved",
          partial_result: result
        }
      end
    end
    
    private
    
    def execute_with_adaptation(plan)
      attempt = 0
      max_attempts = @phase.dig(:adaptive, :max_attempts) || 3
      
      while attempt < max_attempts
        result = try_execution(plan)
        
        return result if result[:success]
        
        # Adapt plan based on failure
        plan = adapt_plan(plan, result[:error])
        attempt += 1
      end
      
      { success: false, error: "Max attempts reached" }
    end
  end
end
```

#### 4. **ValidationExecutor**
```ruby
module Agents
  class ValidationExecutor < PhaseExecutor
    def execute
      validation_results = []
      all_passed = true
      
      @phase[:validation_rules].each do |rule|
        result = run_validation(rule)
        validation_results << result
        
        if !result[:passed]
          all_passed = false
          
          # Attempt fix if configured
          if @phase.dig(:on_failure, :action) == 'attempt_fix'
            fix_result = attempt_fix(rule, result)
            result[:fix_attempted] = true
            result[:fix_result] = fix_result
            all_passed = fix_result[:success] if fix_result
          end
        end
      end
      
      {
        success: all_passed,
        validation_results: validation_results,
        phase: @phase[:id]
      }
    end
    
    private
    
    def run_validation(rule)
      case rule[:type]
      when 'tool'
        # Use a tool to validate
        ToolCatalog.execute_tool(rule[:tool], {}, @context)
      when 'function'
        # Run custom validation function
        eval(rule[:validation_function])
      when 'ai_check'
        # Use AI to validate
        ai_validate(rule[:check])
      end
    end
  end
end
```

#### 5. **WorkflowEngineV2** (Enhanced)
```ruby
class WorkflowEngineV2 < WorkflowEngine
  def execute_workflow(workflow_spec, initial_inputs = {})
    # Check template version
    if workflow_spec[:template_version] == 2
      execute_v2_workflow(workflow_spec, initial_inputs)
    else
      # Fallback to V1 execution
      super
    end
  end
  
  private
  
  def execute_v2_workflow(workflow_spec, initial_inputs)
    # Execute phases instead of steps
    phases = workflow_spec[:phases]
    
    phases.each do |phase|
      # Select appropriate executor
      executor = select_phase_executor(phase)
      
      # Execute phase
      result = executor.execute
      
      # Handle result
      if result[:success]
        # Store phase output
        store_phase_result(phase[:id], result)
      else
        # Handle failure
        handle_phase_failure(phase, result)
      end
      
      # Check if we should stop
      break if should_stop_workflow?(result)
    end
  end
  
  def select_phase_executor(phase)
    case phase[:type]
    when 'gather_context'
      Agents::GatherContextExecutor.new(phase, @context)
    when 'execute_goal'
      Agents::GoalExecutor.new(phase, @context)
    when 'validate_result'
      Agents::ValidationExecutor.new(phase, @context)
    else
      raise "Unknown phase type: #{phase[:type]}"
    end
  end
end
```

---

## Migration Strategy

### Phase 1: Foundation (Week 1)
- [ ] Create phase executor base classes
- [ ] Implement GatherContextExecutor
- [ ] Add template version detection in WorkflowEngineV2
- [ ] Create V2 template validation

### Phase 2: Core Executors (Week 2)
- [ ] Implement GoalExecutor with adaptive execution
- [ ] Implement ValidationExecutor
- [ ] Add phase result storage in WorkflowContext
- [ ] Update PlannerAgentService to handle V2 templates

### Phase 3: Context Integration (Week 3)
- [ ] Enhance WorkflowContext integration
- [ ] Add intelligent context source checking
- [ ] Implement AI-powered data extraction from files
- [ ] Add conversational prompt generation

### Phase 4: Template Migration (Week 4)
- [ ] Convert landing_page_creation to V2
- [ ] Convert campaign templates to V2
- [ ] Create V2 template authoring guide
- [ ] Build template testing framework

### Phase 5: UI Enhancement (Week 5)
- [ ] Update frontend to handle V2 phase updates
- [ ] Enhance streaming for conversational flow
- [ ] Add phase progress visualization
- [ ] Improve canvas types for V2 workflows

### Phase 6: Testing & Refinement (Week 6)
- [ ] End-to-end testing of V2 workflows
- [ ] Performance optimization
- [ ] Error handling refinement
- [ ] Documentation and examples

---

## V2 Template Examples

### Example 1: Landing Page Creation V2
```yaml
template_version: 2
name: "AI-Powered Landing Page Creation V2"
slug: "landing_page_creation_v2"
description: "Create professional landing pages conversationally"
category: "content_generation"

config:
  execution_mode: "adaptive"
  context_aware: true
  conversational: true
  self_healing: true

keywords:
  - landing page
  - create page
  - build website

phases:
  # Phase 1: Understand what's needed
  - id: "discovery"
    type: "gather_context"
    name: "Understand Requirements"
    goal: "Gather all info needed for landing page"
    
    required_knowledge:
      business:
        - name
        - industry
        - value_proposition
      audience:
        - target_audience
        - pain_points
      design:
        - style_preference
        - brand_colors
        - images
      content:
        - headline
        - cta_text
        - key_features
    
    context_sources:
      priority:
        - workflow_context
        - conversation_history
        - entity_profile
        - direct_conversation
    
    extraction_strategies:
      workflow_context:
        file_types:
          pdf: "Extract brand guide, business info"
          image: "Analyze for colors and style"
          docx: "Extract content and messaging"
    
    ai_instructions: |
      Gather landing page requirements intelligently.
      
      1. CHECK UPLOADED FILES FIRST
         - Brand guides: Extract name, colors, fonts, value prop
         - Images: Analyze style, colors, subject matter
         - Documents: Extract messaging, features, benefits
      
      2. REVIEW CONVERSATION
         - Look for business description
         - Find audience mentions
         - Identify goals stated
      
      3. CHECK ENTITY PROFILE
         - Use known business name
         - Use industry if available
      
      4. ASK CONVERSATIONALLY (only for gaps)
         - Be natural and friendly
         - Ask related questions together
         - Confirm instead of asking from scratch
         
      Example: "I can see from your brand guide that you're 
      targeting small businesses with accounting software. 
      What's the main problem you solve for them?"
    
    allowed_tools:
      - get_workflow_context
      - analyze_document
      - extract_colors_from_image
      - get_data
    
    completion_criteria:
      all_required_knowledge_gathered: true
  
  # Phase 2: Create the page
  - id: "creation"
    type: "execute_goal"
    name: "Build Landing Page"
    goal: "Create a professional, conversion-optimized landing page"
    
    requires_from_previous:
      - business
      - audience
      - design
      - content
    
    execution_strategy:
      approach: "adaptive"
      
      allowed_tools:
        - generate_ai_landing_page
        - update_landing_page_content
        - create_object
        - get_workflow_context
      
      constraints:
        must_use_uploaded_images: true
        must_include_cta: true
        max_ai_calls: 5
      
      success_when:
        - landing_page_id_exists: true
        - html_generated: true
        - responsive_design: true
    
    ai_instructions: |
      Build the landing page with gathered context.
      
      INTELLIGENT CREATION:
      1. Get uploaded images from workflow_context
      2. Use extracted brand colors
      3. Create page with generate_ai_landing_page
      4. Include all required sections:
         - Hero with CTA
         - Features/Benefits
         - Social proof (if available)
         - Final CTA
      
      5. Ensure responsive design
      6. Optimize for conversion
      
      You can chain tools and self-heal if issues arise.
    
    adaptive:
      enabled: true
      max_attempts: 3
      self_healing: true
  
  # Phase 3: Validate quality
  - id: "validation"
    type: "validate_result"
    name: "Quality Check"
    goal: "Ensure landing page meets quality standards"
    
    validation_rules:
      - rule: "responsive_design"
        check: "Works on all devices"
        tool: "check_responsive"
        
      - rule: "has_cta"
        check: "Clear call-to-action present"
        
      - rule: "images_valid"
        check: "All images load properly"
        tool: "verify_image_urls"
        
      - rule: "brand_consistent"
        check: "Uses brand colors from upload"
    
    on_failure:
      action: "attempt_fix"
      max_fix_attempts: 2
      use_fixer_agent: true

success_criteria:
  - landing_page_created: true
  - quality_validated: true
  - user_satisfied: true
```

### Example 2: Campaign Creation V2
```yaml
template_version: 2
name: "Email Campaign Builder V2"
slug: "email_campaign_v2"
description: "Create email campaigns conversationally"
category: "campaign_creation"

phases:
  - id: "gather_campaign_details"
    type: "gather_context"
    name: "Campaign Details"
    
    required_knowledge:
      campaign_basics:
        - name
        - type
        - goal
      targeting:
        - audience_segment
        - contact_groups
      content:
        - message_theme
        - email_template
    
    context_sources:
      priority:
        - workflow_context
        - conversation_history
        - direct_conversation
    
    ai_instructions: |
      Gather campaign requirements naturally.
      
      Check if user mentioned:
      - Campaign purpose
      - Target audience
      - Existing template to use
      
      Only ask for what's missing.
      Be conversational and helpful.
    
    allowed_tools:
      - get_workflow_context
      - get_data  # To show available templates
  
  - id: "setup_campaign"
    type: "execute_goal"
    name: "Create Campaign"
    goal: "Set up the email campaign with all components"
    
    execution_strategy:
      approach: "adaptive"
      allowed_tools:
        - create_object
        - update_object
        - get_data
      
      success_when:
        - campaign_created: true
        - template_linked: true
        - contacts_added: true
    
    ai_instructions: |
      Create the campaign intelligently:
      1. Create campaign object
      2. Link email template
      3. Add contact groups
      4. Set scheduling if specified
      
      Handle errors gracefully and retry if needed.
```

---

## Key Differentiators from V1

| Aspect | V1 (Current) | V2 (Proposed) |
|--------|-------------|---------------|
| **Structure** | Rigid steps | Flexible phases |
| **Data Collection** | Forms | Conversational + Context |
| **Tool Usage** | Prescriptive | Adaptive |
| **Context** | Ignored | First-class |
| **File Handling** | Manual | Automatic extraction |
| **User Experience** | Interruptions | Natural flow |
| **Intelligence** | Low (scripted) | High (AI-driven) |
| **Resilience** | Brittle | Self-healing |
| **Learning** | None | Context accumulation |

---

## Success Metrics

### User Experience
- ✅ 80% reduction in form interactions
- ✅ 90% context reuse from uploads
- ✅ 3x faster task completion
- ✅ 50% fewer user inputs required

### System Performance
- ✅ 70% fewer AI calls (via context reuse)
- ✅ 90% workflow success rate (self-healing)
- ✅ Real-time streaming maintained
- ✅ <500ms phase transition time

### Developer Experience
- ✅ 50% less template code
- ✅ Easier template authoring
- ✅ Better debugging (phase-level logs)
- ✅ Reusable phase executors

---

## Risk Mitigation

### Risk: Templates too flexible, hard to debug
**Mitigation:**
- Comprehensive logging at phase level
- Phase execution history in WorkflowContext
- Replay capability for failed workflows

### Risk: AI makes wrong decisions
**Mitigation:**
- Validation phases catch errors
- FixerAgent for corrections
- Fallback to V1-style execution if V2 fails

### Risk: Performance degradation
**Mitigation:**
- Cache context lookups
- Limit AI calls per phase
- Timeout and budget constraints

### Risk: Breaking existing workflows
**Mitigation:**
- V1 and V2 run in parallel
- Gradual migration template by template
- Version detection ensures compatibility

---

## Conclusion

Workflow Template V2 represents a fundamental shift from **prescriptive automation** to **intelligent assistance**. By making templates context-aware, conversational, and adaptive, we create a system that:

1. **Works with users, not against them** - Natural conversation, minimal interruption
2. **Learns from context** - Uses uploaded files, history, and profile data
3. **Adapts to situations** - Self-heals, chooses tools intelligently
4. **Scales elegantly** - Easier to author, maintain, and extend

The architecture leverages existing strengths (multi-agent system, streaming UI, tool catalog) while addressing core limitations (rigid execution, poor UX, no context awareness).

**Next Steps:**
1. Review and approve this design
2. Begin Phase 1 implementation
3. Convert one template to V2 as POC
4. Iterate based on learnings
5. Scale to all templates

This is the foundation for a truly intelligent, conversational automation platform.
