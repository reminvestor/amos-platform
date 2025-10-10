# Interactive Task Framework Design Guide

## 🎯 Overview

The Interactive Task Framework extends Scout's current autonomous task system to handle complex, multi-step processes that require user collaboration and input. This enables Scout to handle sophisticated creative tasks like landing page design, campaign strategy, and content creation.

## 🔄 Task Types

### **Autonomous Tasks** (Current System)
- **Definition**: Tasks Scout can complete independently with available data
- **Examples**: Create campaign, link template, get analytics, query data
- **Flow**: User request → Task list → Execute tools → Complete
- **UI**: Task progress canvas with checkboxes
- **When to Use**: Clear, data-driven tasks with no ambiguity

### **Interactive Tasks** (New System) 
- **Definition**: Tasks requiring user input, feedback, or creative collaboration
- **Examples**: Create landing page, design campaign strategy, content creation
- **Flow**: User request → Wizard canvas → Collect input → Generate → Iterate → Complete
- **UI**: Interactive wizard with forms, previews, and validation steps
- **When to Use**: Creative tasks, complex configurations, user-specific customization

### **Hybrid Tasks** (Future Enhancement)
- **Definition**: Mix of autonomous and interactive steps
- **Examples**: "Create campaign with custom landing page" (autonomous campaign creation + interactive page design)
- **Flow**: Dynamic switching between task modes based on step requirements
- **UI**: Combined task progress + wizard interface

## 🏗️ Architecture

### **1. Task Mode Detection**
```javascript
// AI Service Enhancement
class TaskModeDetector {
  detectMode(userMessage) {
    // Keywords that trigger interactive mode
    const interactiveKeywords = [
      'create landing page', 'design page', 'build website',
      'campaign strategy', 'content creation', 'custom design'
    ];
    
    // Return: 'autonomous', 'interactive', or 'hybrid'
  }
}
```

### **2. Canvas System Extension**
```ruby
# New Canvas Types
- task_progress      # Current autonomous task system
- interactive_wizard # New interactive wizard system  
- hybrid_workflow    # Future: combined interface
```

### **3. Interactive Step Types**
```javascript
const INTERACTIVE_STEPS = {
  'user_input': {
    type: 'form',
    fields: [...],
    validation: {...}
  },
  'choice_selection': {
    type: 'options',
    choices: [...],
    allowMultiple: boolean
  },
  'content_preview': {
    type: 'preview',
    content: '...',
    actions: ['approve', 'modify', 'regenerate']
  },
  'iterative_refinement': {
    type: 'feedback',
    current: '...',
    prompt: 'What would you like to change?'
  }
}
```

## 🎨 Landing Page Wizard Flow (Primary Use Case)

### **Step 1: Intent Detection**
```
User: "Create a landing page for my consulting business"
AI: Detects → Interactive Mode → Loads wizard canvas
```

### **Step 2: Information Gathering**
```javascript
// Wizard Step 1: Business Information
{
  step: 'business_info',
  fields: {
    business_name: 'text',
    industry: 'select',
    target_audience: 'textarea',
    key_message: 'textarea'
  }
}
```

### **Step 3: Design Preferences**
```javascript
// Wizard Step 2: Design Choices
{
  step: 'design_preferences',
  fields: {
    page_type: 'select', // lead_generation, product_launch, etc.
    color_scheme: 'color_picker',
    style: 'radio', // professional, modern, creative
    cta_focus: 'text'
  }
}
```

### **Step 4: Content Generation**
```javascript
// Wizard Step 3: AI Generation
{
  step: 'generation',
  type: 'processing',
  message: 'Creating your landing page...',
  tools: ['generate_ai_landing_page']
}
```

### **Step 5: Preview & Refinement**
```javascript
// Wizard Step 4: Review & Iterate
{
  step: 'preview',
  type: 'preview',
  content: '<generated_html>',
  actions: {
    approve: 'Looks great!',
    modify: 'Make changes...',
    regenerate: 'Start over'
  }
}
```

## 🔧 Implementation Plan

### **Phase 1: Core Infrastructure**
1. ✅ **Task Mode Detection Service**
   - Extend `ScoutGenericToolsService` with mode detection
   - Add interactive keywords and patterns
   - Route to appropriate canvas type

2. ✅ **Interactive Canvas System**
   - Create `interactive_wizard` canvas type
   - Build wizard step management
   - Add step validation and navigation

3. ✅ **Wizard State Management**
   - Store wizard progress in Rails cache
   - Handle step transitions and data persistence
   - Support step validation and error handling

### **Phase 2: Landing Page Integration**
1. ✅ **Landing Page Wizard Canvas**
   - Design multi-step form interface
   - Integrate with existing `generate_ai_landing_page` tool
   - Add preview and iteration capabilities

2. ✅ **AI Conversation Integration**
   - Update system prompts for interactive mode
   - Handle wizard state in AI responses
   - Support conversational refinement

### **Phase 3: Enhanced Features**
1. ✅ **Conditional Logic**
   - Dynamic step flows based on user choices
   - Skip irrelevant steps automatically
   - Branch wizard paths for different use cases

2. ✅ **Real-time Previews**
   - Live HTML preview updates
   - Instant feedback on changes
   - Mobile/desktop preview modes

### **Phase 4: Extensibility**
1. ✅ **Additional Wizard Types**
   - Campaign strategy wizard
   - Email template designer
   - Contact import wizard

2. ✅ **Hybrid Task Support**
   - Seamless switching between autonomous and interactive modes
   - Complex multi-phase workflows
   - Smart mode recommendations

## 📁 File Structure

```
app/
├── services/
│   ├── interactive_task_service.rb          # Core interactive task logic
│   ├── wizard_state_manager.rb              # Wizard state management
│   └── task_mode_detector.rb                # Autonomous vs Interactive detection
├── controllers/
│   └── scout_controller.rb                  # Add interactive canvas routes
├── views/
│   └── scout/canvas/
│       ├── _interactive_wizard.html.erb     # Main wizard canvas
│       ├── _landing_page_wizard.html.erb    # Landing page specific wizard
│       └── _wizard_steps/                   # Individual step partials
│           ├── _business_info.html.erb
│           ├── _design_preferences.html.erb
│           └── _preview_refinement.html.erb
└── javascript/
    └── controllers/
        └── wizard_controller.js              # Stimulus controller for wizard UI
```

## 🎯 Success Criteria

### **User Experience Goals**
- ✅ **Intuitive Flow**: Users understand each step and what's expected
- ✅ **Progressive Disclosure**: Information requested when needed, not overwhelming
- ✅ **Fast Iteration**: Quick preview and refinement cycles
- ✅ **Smart Defaults**: AI provides intelligent suggestions based on input
- ✅ **Seamless Integration**: Feels natural within Scout's existing interface

### **Technical Goals**
- ✅ **State Persistence**: Wizard progress survives page refreshes
- ✅ **Error Handling**: Graceful handling of validation errors and failures
- ✅ **Performance**: Fast step transitions and preview generation
- ✅ **Extensibility**: Easy to add new wizard types and steps
- ✅ **Backwards Compatibility**: Existing autonomous tasks continue to work

## 🚀 Future Enhancements

### **Advanced AI Integration**
- **Conversational Refinement**: "Make the headline more exciting" → AI updates and shows preview
- **Smart Suggestions**: AI proactively suggests improvements based on best practices
- **Context Awareness**: Remember user preferences across different wizards

### **Collaboration Features**
- **Multi-user Workflows**: Team members can contribute to wizard steps
- **Approval Processes**: Stakeholder review and approval steps
- **Version History**: Track changes and allow rollback to previous versions

### **Analytics & Optimization**
- **Wizard Analytics**: Track step completion rates and abandonment points
- **A/B Testing**: Test different wizard flows and step orders
- **Performance Metrics**: Measure task completion success rates

## 📝 Implementation Notes

### **Key Design Principles**
1. **User-Centric**: Every step should provide clear value to the user
2. **Contextual**: Information gathering should feel natural and conversational
3. **Iterative**: Support rapid refinement and improvement cycles
4. **Intelligent**: AI should anticipate needs and provide smart defaults
5. **Extensible**: Framework should easily support new use cases

### **Technical Considerations**
- **State Management**: Use Rails cache with appropriate expiration
- **Error Recovery**: Graceful degradation when steps fail
- **Mobile Support**: Ensure wizard works well on all device sizes
- **Accessibility**: Follow WCAG guidelines for form interactions
- **Security**: Validate all user inputs and sanitize content

---

*This framework will transform Scout from a task executor into a true collaborative AI assistant, capable of handling complex creative workflows while maintaining the efficiency of autonomous operations.*
