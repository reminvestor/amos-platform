class TaskModeDetector
  # Keywords that strongly indicate different modes
  INTERACTIVE_KEYWORDS = [
    # Creative tasks
    'create landing page', 'design page', 'build website', 'design landing',
    'landing page for', 'website for', 'web page', 'landing page',
    
    # Strategy tasks
    'campaign strategy', 'marketing strategy', 'content strategy',
    'help me plan', 'brainstorm', 'suggest ideas',
    
    # Content creation
    'write content', 'create content', 'draft email', 'compose message',
    'help me write', 'improve my', 'rewrite this',
    
    # Design tasks
    'design layout', 'choose colors', 'pick theme', 'style options',
    'make it look', 'visual design', 'ui design'
  ].freeze
  
  AUTONOMOUS_KEYWORDS = [
    # Data queries
    'show campaigns', 'list contacts', 'get analytics', 'view reports',
    'how many', 'what is the', 'show me data', 'pull data',
    
    # Direct actions
    'create campaign', 'send email', 'update contact', 'delete',
    'link template', 'schedule campaign', 'export data',
    
    # System queries
    'check status', 'is running', 'last run', 'show errors',
    'system health', 'performance metrics'
  ].freeze
  
  # Patterns that indicate hybrid workflows
  HYBRID_PATTERNS = [
    /create campaign.*(landing page|custom content)/i,
    /design.*(and|then|with).*(send|launch|deploy)/i,
    /build.*(test|preview).*(approve|launch)/i
  ].freeze
  
  def detect(user_message)
    # Normalize message
    normalized_message = user_message.downcase.strip
    
    # Calculate scores for each mode
    interactive_score = calculate_interactive_score(normalized_message)
    autonomous_score = calculate_autonomous_score(normalized_message)
    hybrid_score = calculate_hybrid_score(normalized_message)
    
    # Determine mode and confidence
    mode, confidence = determine_mode_and_confidence(
      interactive_score, 
      autonomous_score, 
      hybrid_score,
      normalized_message
    )
    
    # Detect missing inputs
    missing_inputs = detect_missing_inputs(normalized_message, mode)
    
    # Generate rationale
    rationale = generate_rationale(normalized_message, mode, confidence)
    
    # Build response
    {
      mode: mode,
      confidence: confidence,
      rationale: rationale,
      missing_inputs: missing_inputs,
      scores: {
        interactive: interactive_score,
        autonomous: autonomous_score,
        hybrid: hybrid_score
      },
      suggested_workflow: suggest_workflow(mode, normalized_message)
    }
  end
  
  private
  
  def calculate_interactive_score(message)
    score = 0.0
    
    # Check for exact keyword matches (only add once per message)
    if INTERACTIVE_KEYWORDS.any? { |keyword| message.include?(keyword) }
      score += 0.4
    end
    
    # Check for creative/subjective language
    creative_words = ['beautiful', 'modern', 'professional', 'attractive', 'engaging', 'compelling']
    creative_words.each do |word|
      score += 0.1 if message.include?(word)
    end
    
    # Check for user preferences language
    preference_words = ['want', 'like', 'prefer', 'need', 'looking for', 'hoping']
    preference_words.each do |word|
      score += 0.1 if message.include?(word)
    end
    
    # Boost for questions about options
    score += 0.2 if message.include?('?') && message.match?(/what|which|how should/i)
    
    [score, 1.0].min
  end
  
  def calculate_autonomous_score(message)
    score = 0.0
    
    # Check for exact keyword matches (only add once per message)
    if AUTONOMOUS_KEYWORDS.any? { |keyword| message.include?(keyword) }
      score += 0.4
    end
    
    # Check for data/action language
    data_words = ['show', 'list', 'get', 'fetch', 'display', 'export', 'count']
    data_words.each do |word|
      score += 0.1 if message.include?(word)
    end
    
    # Check for specific entity references
    entity_words = ['campaign', 'contact', 'template', 'email', 'analytics']
    entity_count = entity_words.count { |word| message.include?(word) }
    score += 0.1 * entity_count
    
    # Boost for direct commands
    score += 0.2 if message.match?(/^(create|update|delete|show|list|get)\s/i)
    
    [score, 1.0].min
  end
  
  def calculate_hybrid_score(message)
    score = 0.0
    
    # Check hybrid patterns
    HYBRID_PATTERNS.each do |pattern|
      score += 0.4 if message.match?(pattern)
    end
    
    # Check for multi-step indicators
    multistep_words = ['and then', 'after that', 'followed by', 'once', 'when complete']
    multistep_words.each do |phrase|
      score += 0.2 if message.include?(phrase)
    end
    
    # Check for both creative and action words
    has_creative = INTERACTIVE_KEYWORDS.any? { |k| message.include?(k) }
    has_action = AUTONOMOUS_KEYWORDS.any? { |k| message.include?(k) }
    score += 0.3 if has_creative && has_action
    
    [score, 1.0].min
  end
  
  def determine_mode_and_confidence(interactive, autonomous, hybrid, message)
    # Handle edge cases - short messages are usually greetings/conversation
    if message.length < 10
      return ['autonomous', 0.6] # Simple conversation
    end
    
    # Check for conversational patterns first
    conversational_patterns = [
      /\b(hello|hi|hey|thanks|thank you|ok|okay|yes|no|bye|goodbye)\b/i,
      /\b(what|who|when|where|why|how)\s+(is|are|was|were|does|do|did)\s+(your|the|a|an)\b/i,
      /\b(tell me about|explain|describe|help me understand)\b/i,
      /\b(can you|could you|would you|will you)\b/i,
      /^(what|who|when|where|why|how|is|are|can|could|would|does|do)\b/i
    ]
    
    if conversational_patterns.any? { |pattern| message.match?(pattern) }
      # Check if it's ALSO asking for a specific task
      if interactive > 0.7 || autonomous > 0.7 || hybrid > 0.5
        # It's both conversational AND task-oriented, let the scores decide
      else
        # Pure conversational query
        return ['autonomous', 0.7]
      end
    end
    
    # Check hybrid first as it's most specific
    if hybrid > 0.5
      return ['hybrid', hybrid]
    end
    
    # Then check interactive vs autonomous
    if interactive > autonomous
      confidence = interactive > 0.5 ? interactive : interactive * 0.8
      ['interactive', confidence]
    elsif autonomous > interactive
      confidence = autonomous > 0.5 ? autonomous : autonomous * 0.9
      ['autonomous', confidence]
    else
      # Default to autonomous for unclear requests
      ['autonomous', 0.4]
    end
  end
  
  def detect_missing_inputs(message, mode)
    missing = []
    
    case mode
    when 'interactive'
      # Check for landing page specific inputs
      if message.match?(/landing page|website/i)
        missing << 'business_name' unless message.match?(/for\s+(\w+)/i)
        missing << 'target_audience' unless message.match?(/audience|customers?|users?|visitors?/i)
        missing << 'style_preference' unless message.match?(/style|design|theme|look/i)
      end
    when 'autonomous'
      # Check for required parameters
      if message.match?(/create campaign/i)
        missing << 'campaign_name' unless message.match?(/called|named|"\w+"/i)
        missing << 'contact_group' unless message.match?(/contacts?|group|list/i)
      end
    end
    
    missing
  end
  
  def generate_rationale(message, mode, confidence)
    case mode
    when 'interactive'
      if confidence > 0.7
        "This request involves creative decisions and user preferences that benefit from guided interaction."
      else
        "This request seems to involve subjective choices. Using interactive mode to ensure we capture your vision correctly."
      end
    when 'autonomous'
      if confidence > 0.7
        "This is a straightforward data operation that can be completed automatically."
      else
        "This appears to be a direct action request. Proceeding with autonomous execution."
      end
    when 'hybrid'
      "This request involves both automated tasks and creative decisions. Using hybrid workflow for optimal results."
    end
  end
  
  def suggest_workflow(mode, message)
    case mode
    when 'interactive'
      if message.match?(/landing page/i)
        'landing_page_wizard'
      elsif message.match?(/campaign/i)
        'campaign_strategy_wizard'
      else
        'generic_interactive_wizard'
      end
    when 'autonomous'
      'direct_execution'
    when 'hybrid'
      'multi_phase_workflow'
    end
  end
end
