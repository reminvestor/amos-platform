# Interactive Task Framework V2 - Progressive Enhancement Guide

## 🎯 Overview

This updated design incorporates architectural improvements while maintaining a pragmatic upgrade path. We'll evolve the system incrementally, starting with high-impact changes that don't require ripping out existing functionality.

## 🔄 Core Architecture Shift

### **From: Wizard-Centric → To: Workflow-Centric**

Instead of thinking "wizard UI with state", we think **"workflow engine that can render as a wizard"**. This mental model shift enables:
- Better state management (database-backed, not cache)
- Multi-agent orchestration
- Hybrid task flows as emergent behavior
- Better observability and debugging

## 📈 Progressive Enhancement Plan

### **Phase 0: Foundation Improvements (No Breaking Changes)**

#### 1. **Enhanced Mode Detection**
```ruby
# app/services/task_mode_detector.rb
class TaskModeDetector
  def detect(user_message)
    # Quick pattern matching with confidence scoring
    confidence = calculate_confidence(user_message)
    mode = initial_mode_guess(user_message)
    
    # Fallback to interactive if low confidence
    if confidence < 0.7
      mode = 'interactive'
    end
    
    {
      mode: mode,
      confidence: confidence,
      rationale: generate_rationale(user_message, mode),
      missing_inputs: detect_missing_inputs(user_message)
    }
  end
  
  private
  
  def calculate_confidence(message)
    # Start simple: keyword matching + length heuristics
    # Later: upgrade to small classifier
    keywords = extract_keywords(message)
    
    case
    when has_creative_keywords?(keywords) then 0.9
    when has_data_keywords?(keywords) then 0.85
    when message.length < 20 then 0.4  # Too vague
    else 0.6
    end
  end
end
```

#### 2. **Persistent Task Sessions (Database-Backed)**
```ruby
# app/models/task_session.rb
class TaskSession < ApplicationRecord
  belongs_to :user
  has_many :task_events
  
  # Store state in JSONB column instead of Rails cache
  store_accessor :state, :current_step, :wizard_data, :workflow_spec
  
  def current_state
    # Build current state from events if needed
    state || reconstruct_from_events
  end
  
  def add_event(type, payload)
    task_events.create!(
      event_type: type,
      payload: payload,
      created_at: Time.current
    )
  end
end

# Migration
class CreateTaskSessions < ActiveRecord::Migration[7.1]
  def change
    create_table :task_sessions do |t|
      t.references :user, null: false
      t.string :status, default: 'active'
      t.jsonb :state, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    
    create_table :task_events do |t|
      t.references :task_session, null: false
      t.string :event_type, null: false
      t.jsonb :payload, default: {}
      t.datetime :created_at, null: false
    end
    
    add_index :task_sessions, :status
    add_index :task_events, [:task_session_id, :created_at]
  end
end
```

### **Phase 1: Landing Page DSL (Safer HTML Generation)**

#### **Landing Page DSL Specification**
```ruby
# app/models/landing_page_dsl.rb
class LandingPageDSL
  SCHEMA = {
    type: 'object',
    required: ['page'],
    properties: {
      page: {
        type: 'object',
        properties: {
          theme: { enum: ['clean', 'modern', 'bold'] },
          sections: {
            type: 'array',
            items: { 
              oneOf: [
                { '$ref': '#/definitions/hero' },
                { '$ref': '#/definitions/features' },
                { '$ref': '#/definitions/cta' }
              ]
            }
          }
        }
      }
    },
    definitions: {
      hero: {
        type: 'object',
        properties: {
          headline: { type: 'string', maxLength: 100 },
          subtext: { type: 'string', maxLength: 200 },
          cta: {
            type: 'object',
            properties: {
              label: { type: 'string' },
              action: { type: 'string' }
            }
          }
        }
      }
      # ... other section types
    }
  }
  
  def self.validate(dsl_content)
    JSON::Validator.validate(SCHEMA, dsl_content)
  end
  
  def self.compile_to_html(dsl_content, options = {})
    # Safe HTML generation from constrained DSL
    compiler = LandingPageCompiler.new(dsl_content, options)
    compiler.compile
  end
end
```

#### **Updated Landing Page Generation**
```ruby
# app/services/ai_agents/landing_page_agent.rb
class LandingPageAgent < BaseAgent
  def generate(inputs)
    # AI generates DSL instead of raw HTML
    prompt = build_dsl_prompt(inputs)
    
    dsl_response = ai_service.generate(prompt, {
      response_format: { type: "json_object" }
    })
    
    # Validate DSL
    unless LandingPageDSL.validate(dsl_response)
      raise "Invalid DSL generated"
    end
    
    # Store both DSL and compiled HTML
    {
      dsl: dsl_response,
      html: LandingPageDSL.compile_to_html(dsl_response),
      preview_html: LandingPageDSL.compile_to_html(dsl_response, preview: true)
    }
  end
end
```

### **Phase 2: Lightweight Workflow Engine**

#### **Simple Workflow Model**
```ruby
# app/models/workflow.rb
class Workflow
  attr_reader :steps, :current_step
  
  def initialize(spec)
    @spec = spec
    @steps = build_steps(spec)
    @current_step = find_next_step
  end
  
  def execute_next_step(inputs = {})
    return if completed?
    
    step = @current_step
    
    # Check if we need user input
    if step.requires_input? && inputs.empty?
      return { status: 'awaiting_input', step: step }
    end
    
    # Execute the step
    result = step.execute(inputs)
    
    # Move to next step
    @current_step = find_next_step
    
    result
  end
  
  private
  
  def build_steps(spec)
    spec[:steps].map do |step_spec|
      Step.new(step_spec)
    end
  end
end

# app/models/step.rb
class Step
  attr_reader :id, :type, :config
  
  def initialize(spec)
    @id = spec[:id]
    @type = spec[:type]
    @config = spec[:config]
    @status = 'pending'
  end
  
  def requires_input?
    @type == 'user_input' || @config[:requires_input]
  end
  
  def execute(inputs = {})
    case @type
    when 'tool_call'
      ToolRunner.new.call(tool: @config[:tool], inputs: inputs)
    when 'user_input'
      { status: 'awaiting_input', form: @config[:form] }
    else
      raise "Unknown step type: #{@type}"
    end
  end
end
```

### **Phase 3: Tool Contracts & Safety**

#### **Tool Registry with Contracts**
```ruby
# app/registries/tool_registry.rb
class ToolRegistry
  TOOLS = {
    generate_landing_page: {
      version: '1.0',
      input_schema: {
        type: 'object',
        required: ['business_info', 'design_preferences'],
        properties: {
          business_info: {
            type: 'object',
            properties: {
              name: { type: 'string' },
              industry: { type: 'string' },
              target_audience: { type: 'string' }
            }
          },
          design_preferences: {
            type: 'object',
            properties: {
              style: { enum: ['professional', 'modern', 'creative'] },
              color_scheme: { type: 'string' }
            }
          }
        }
      },
      output_schema: {
        type: 'object',
        required: ['dsl', 'preview_html'],
        properties: {
          dsl: { type: 'object' },
          preview_html: { type: 'string' }
        }
      }
    }
  }
  
  def self.validate_inputs(tool_name, inputs)
    schema = TOOLS[tool_name][:input_schema]
    JSON::Validator.validate(schema, inputs)
  end
  
  def self.validate_outputs(tool_name, outputs)
    schema = TOOLS[tool_name][:output_schema]
    JSON::Validator.validate(schema, outputs)
  end
end
```

## 🔧 Implementation Roadmap

### **Week 1: Foundation**
1. ✅ Create `TaskSession` model and migration
2. ✅ Update `ScoutController` to use `TaskSession` instead of Rails cache
3. ✅ Implement basic `TaskModeDetector` with confidence scoring
4. ✅ Add event logging for auditability

### **Week 2: DSL & Safety**
1. ✅ Implement Landing Page DSL specification
2. ✅ Create DSL → HTML compiler with component whitelist
3. ✅ Update landing page agent to generate DSL
4. ✅ Add preview sandboxing (iframe with CSP)

### **Week 3: Workflow Engine**
1. ✅ Create lightweight `Workflow` and `Step` models
2. ✅ Implement `ToolRunner` with contract validation
3. ✅ Update interactive wizard to use workflow engine
4. ✅ Add progress tracking and resumability

### **Week 4: Observability & Polish**
1. ✅ Add performance metrics (token usage, latencies)
2. ✅ Implement retry logic with exponential backoff
3. ✅ Add user analytics events
4. ✅ Create evaluation test suite

## 🎯 Key Improvements Over V1

### **1. State Management**
- ❌ **Before**: Rails cache (ephemeral, no history)
- ✅ **After**: Database-backed with event log (persistent, auditable)

### **2. Mode Detection**
- ❌ **Before**: Simple keyword matching
- ✅ **After**: Confidence scoring with fallback to interactive

### **3. HTML Generation**
- ❌ **Before**: Direct HTML from AI (injection risk)
- ✅ **After**: Constrained DSL → Safe HTML compilation

### **4. Architecture**
- ❌ **Before**: Wizard-centric thinking
- ✅ **After**: Workflow engine that can render as wizard

### **5. Tool Execution**
- ❌ **Before**: Direct tool calls without validation
- ✅ **After**: Contract validation + idempotency

## 📊 Migration Strategy

### **Existing Code Compatibility**
```ruby
# Adapter pattern to maintain backward compatibility
class TaskSystemAdapter
  def self.handle_request(user, message, mode = nil)
    # Try new system first
    if FeatureFlag.enabled?(:new_task_system, user)
      task_session = TaskSession.create!(user: user)
      detector = TaskModeDetector.new
      mode_info = detector.detect(message)
      
      if mode_info[:mode] == 'autonomous' && mode_info[:confidence] > 0.8
        # Use existing autonomous system
        ScoutGenericToolsService.new.process(message)
      else
        # Use new interactive system
        InteractiveTaskService.new(task_session).process(message)
      end
    else
      # Fallback to existing system
      existing_system_handler(message)
    end
  end
end
```

## 🚀 Future Enhancements (Post-MVP)

### **Multi-Agent Orchestration**
- Implement specialized agents (Planner, Designer, Critic)
- Add agent coordination layer
- Enable parallel step execution

### **Advanced Features**
- Real-time collaboration
- A/B testing framework
- Advanced analytics dashboard
- Multi-language support

## 📝 Development Principles

1. **Incremental Enhancement**: Each phase should work independently
2. **Backward Compatibility**: Existing features must continue working
3. **Data Safety**: All user data persisted to database, not cache
4. **Security First**: Validate all inputs/outputs, sanitize HTML
5. **Observable**: Log all significant events for debugging

## 🔍 Success Metrics

- **Technical**: 
  - Zero data loss from session interruptions
  - < 10s workflow step execution (p95)
  - 100% tool contract validation
  
- **User Experience**:
  - > 80% task completion rate
  - < 3 iterations average for landing pages
  - > 90% satisfaction score

---

*This V2 design provides a robust foundation while maintaining a practical upgrade path. We can implement incrementally without breaking existing functionality.*
