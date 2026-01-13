# frozen_string_literal: true

# Model Evaluation Benchmark Suite
# Tests all available models across different task types and rates them
#
# Usage:
#   rake models:evaluate              # Run full evaluation
#   rake models:evaluate[quick]       # Quick test (1 prompt per category)
#   rake models:evaluate[tools_only]  # Test only tool-capable models
#   rake models:list                  # List all available models
#
namespace :models do
  desc "Quick tool usage benchmark - tests which models handle tools correctly"
  task :tools, [:mode] => :environment do |_t, args|
    mode = args[:mode] || 'full'
    
    evaluator = ToolUsageEvaluator.new(mode: mode)
    evaluator.run
  end

  desc "List all available models in the system"
  task list: :environment do
    puts "\n" + "=" * 70
    puts "📊 AVAILABLE MODELS"
    puts "=" * 70

    models = BedrockService::AVAILABLE_MODELS
    
    models.each do |key, config|
      puts "\n#{key}:"
      puts "  ID: #{config[:id]}"
      puts "  Name: #{config[:name]}"
      puts "  Max Tokens: #{config[:max_tokens]}"
      puts "  Context: #{config[:context_window] || 'N/A'}"
      puts "  Cost: $#{config[:cost_per_1m_input]}/1M in, $#{config[:cost_per_1m_output]}/1M out"
      puts "  Vision: #{config[:supports_vision] ? 'Yes' : 'No'}"
      puts "  Caching: #{config[:supports_caching] ? 'Yes' : 'No'}"
    end
    
    puts "\n" + "=" * 70
    puts "Total: #{models.count} models"
    puts "=" * 70
  end

  desc "Evaluate all models across different task types"
  task :evaluate, [:mode] => :environment do |_t, args|
    mode = args[:mode] || 'full'
    
    evaluator = ModelEvaluator.new(mode: mode)
    evaluator.run
  end
end

class ModelEvaluator
  # Models to test - Claude Sonnet 4.5 as baseline reference
  MODELS_TO_TEST = %w[
    claude-sonnet-4-5
    deepseek-v3
    deepseek-r1
    mistral-large-3
    qwen-3-32b
    nemotron-nano-9b
  ].freeze

  # Test categories with CHALLENGING prompts to differentiate models
  TEST_CATEGORIES = {
    content_quality: {
      name: "Content Quality (No Repetition)",
      prompts: [
        # Hard: Long content that tempts repetition
        "Write a comprehensive 500-word article about the future of artificial intelligence in healthcare. Cover diagnosis, treatment, drug discovery, and patient care. Each section must use completely different vocabulary - no repeated phrases across sections.",
        # Hard: Constrained creativity
        "Write 5 unique product descriptions for the same smartphone. Each must highlight different features, use different tones (professional, casual, technical, emotional, minimalist), and share zero repeated phrases.",
        # Hard: Complex explanation without repetition
        "Explain blockchain technology, cryptocurrency, smart contracts, and DeFi in 4 separate paragraphs. Each concept must be explained using completely distinct analogies and vocabulary."
      ],
      evaluation: :check_repetition_strict
    },
    long_form_content: {
      name: "Long Form Content (Landing Page Style)",
      prompts: [
        # Hard: Very specific requirements
        "Write a complete landing page for 'AMOS Labs' - an AI business partner platform. REQUIREMENTS: 1) Hero with exactly 8-word headline, 2) 3 benefits using metaphors (not generic descriptions), 3) Comparison table vs 3 competitors with specific differentiators, 4) 3 customer testimonial quotes with names/titles, 5) Pricing with 3 tiers, 6) FAQ with 4 questions, 7) CTA with urgency. Must be 800+ words.",
        # Hard: Technical + Marketing blend
        "Create a product launch page for an API platform. Include: technical specs (latency, uptime, rate limits with specific numbers), code samples in 2 languages, pricing calculator example, integration steps, and compelling marketing copy. Balance technical accuracy with persuasion.",
        # Hard: Storytelling + Structure
        "Write a founder's letter for a company about-us page. Include: personal origin story (specific moment of inspiration), mission evolution over 5 years (2020-2025), 4 core values with real examples of each in action, team philosophy, and future vision. Must feel authentic, not corporate."
      ],
      evaluation: :check_long_form_strict
    },
    markdown_formatting: {
      name: "Markdown Formatting",
      prompts: [
        # Hard: Complex nested structure
        "Create a technical documentation page with: H1 title, H2 sections for Overview/Installation/API Reference, H3 subsections under each, a table with 5 columns (Method, Endpoint, Params, Returns, Example), nested bullet lists (3 levels deep), numbered steps with sub-steps, inline code, and a code block with syntax highlighting.",
        # Hard: Mixed formatting
        "Write a project status report with: header hierarchy (H1-H4), progress table (Task/Owner/Status/Due), risk matrix table with color indicators described, bullet list of blockers, numbered action items with assignees, blockquote for executive summary, and horizontal rules between sections.",
        # Hard: Precise table formatting
        "Create a feature comparison matrix: 6 products across the top, 10 features down the side, with ✅/❌/⚠️ indicators and footnotes explaining caveats. Include proper table alignment and a legend."
      ],
      evaluation: :check_markdown_strict
    },
    reasoning: {
      name: "Reasoning & Analysis",
      prompts: [
        # Hard: Multi-step calculation
        "A SaaS company has: 10,000 users, $49 ARPU, 4.5% monthly churn, $150 CAC, 18-month average lifetime. Calculate: 1) Current MRR, 2) Annual revenue, 3) LTV, 4) LTV:CAC ratio, 5) Net revenue retention assuming 2% expansion. Then explain if this is a healthy business and what ONE metric to prioritize improving.",
        # Hard: Nuanced tradeoffs
        "Analyze: A startup can either (A) raise $5M at $20M valuation, or (B) grow slower bootstrapped. Consider: control, runway, hiring speed, market timing, founder equity, investor expectations, exit options. Provide a structured framework and a clear recommendation with reasoning.",
        # Hard: Cause and effect chains
        "Trace the second and third-order effects of raising interest rates on: 1) Housing market, 2) Tech startup funding, 3) Consumer spending, 4) Employment. For each, show the causal chain (at least 3 steps) and identify potential feedback loops."
      ],
      evaluation: :check_reasoning_strict
    },
    code_generation: {
      name: "Code Generation",
      prompts: [
        # Hard: Complex algorithm
        "Write a Python function that implements a Least Recently Used (LRU) cache with O(1) get and put operations. Include type hints, docstring, and handle edge cases. Show example usage.",
        # Hard: Full-stack snippet
        "Create a complete HTML/CSS/JavaScript snippet for a real-time search filter: input field, list of 10 items, debounced filtering (300ms), highlight matching text, 'no results' state, and keyboard navigation (up/down arrows). All in one file.",
        # Hard: API design
        "Write a Ruby class for a rate limiter that: allows N requests per time window, uses sliding window algorithm, is thread-safe, includes reset capability, and raises custom exceptions. Include RSpec tests."
      ],
      evaluation: :check_code_strict
    },
    instruction_following: {
      name: "Instruction Following",
      prompts: [
        # Hard: Precise constraints
        "List exactly 7 items. Each item must: start with a different letter (A-G), be exactly 3 words long, relate to technology. Format as a numbered list. Nothing else.",
        # Hard: Format + Content
        "Write a product review in EXACTLY this format:\nRating: [1-5 stars as emoji]\nPros: [3 bullet points]\nCons: [2 bullet points]\nVerdict: [One sentence, max 15 words]\nNo other text before or after.",
        # Hard: Multi-constraint
        "Generate a JSON object with these EXACT fields: 'name' (string, 5-10 chars), 'values' (array of exactly 4 numbers between 1-100), 'active' (boolean), 'meta' (object with 'created' ISO date and 'version' semver string). Valid JSON only, no explanation."
      ],
      evaluation: :check_instructions_strict
    }
  }.freeze

  def initialize(mode: 'full')
    @mode = mode
    @results = {}
    @entity = Entity.first || create_test_entity
    @bedrock = BedrockService.new(entity: @entity)
  end

  def run
    puts "\n" + "=" * 70
    puts "🧪 MODEL EVALUATION BENCHMARK"
    puts "=" * 70
    puts "Mode: #{@mode}"
    puts "Models: #{models_to_test.join(', ')}"
    puts "Categories: #{TEST_CATEGORIES.keys.join(', ')}"
    puts "=" * 70 + "\n"

    models_to_test.each do |model|
      @results[model] = {}
      puts "\n" + "-" * 50
      puts "Testing: #{model}"
      puts "-" * 50

      TEST_CATEGORIES.each do |category, config|
        prompts = @mode == 'quick' ? [config[:prompts].first] : config[:prompts]
        
        puts "\n  📝 #{config[:name]}..."
        
        category_scores = []
        prompts.each_with_index do |prompt, idx|
          print "    Prompt #{idx + 1}/#{prompts.length}... "
          
          result = test_model(model, prompt, config[:evaluation])
          category_scores << result
          
          status = result[:success] ? "✅" : "❌"
          puts "#{status} (#{result[:latency_ms]}ms, score: #{result[:score]}/10)"
          
          if result[:issues].any?
            result[:issues].each { |issue| puts "      ⚠️  #{issue}" }
          end
        end
        
        # Average score for category
        avg_score = (category_scores.sum { |r| r[:score] } / category_scores.length.to_f).round(1)
        avg_latency = (category_scores.sum { |r| r[:latency_ms] } / category_scores.length).round
        
        @results[model][category] = {
          score: avg_score,
          latency_ms: avg_latency,
          details: category_scores
        }
      end
    end

    print_summary
    save_results
  end

  private

  def models_to_test
    case @mode
    when 'tools_only'
      MODELS_TO_TEST.select { |m| %w[mistral-large-3 qwen-3-32b].include?(m) }
    else
      MODELS_TO_TEST
    end
  end

  # Evaluation methods that should use LLM (Sonnet 4.5) as a judge
  LLM_EVALUATED = %i[
    check_repetition_strict
    check_long_form_strict
    check_reasoning_strict
  ].freeze

  def test_model(model, prompt, evaluation_method)
    start_time = Time.current
    
    begin
      # Format as simple messages array - the method handles conversion
      messages = [
        { role: "user", content: prompt }
      ]
      system_prompt = "You are a helpful AI assistant. Follow instructions carefully and provide high-quality responses."
      
      # Harder prompts need more tokens
      tokens = case evaluation_method
               when :check_long_form, :check_long_form_strict then 4000
               when :check_code_strict, :check_reasoning_strict then 3000
               else 2500
               end
      
      response = @bedrock.send_message_converse(
        system_prompt,
        messages,
        model: model,
        max_tokens: tokens,
        temperature: 0.7
      )
      
      latency_ms = ((Time.current - start_time) * 1000).round
      
      # Run evaluation - use LLM judge for subjective evaluations
      if LLM_EVALUATED.include?(evaluation_method)
        evaluation = evaluate_with_llm_judge(prompt, response, evaluation_method)
      else
        evaluation = send(evaluation_method, response)
      end
      
      {
        success: evaluation[:score] >= 6,
        score: evaluation[:score],
        latency_ms: latency_ms,
        issues: evaluation[:issues],
        response_length: response.to_s.length,
        response_preview: response.to_s[0..200]
      }
    rescue => e
      {
        success: false,
        score: 0,
        latency_ms: ((Time.current - start_time) * 1000).round,
        issues: ["Error: #{e.message}"],
        response_length: 0,
        response_preview: ""
      }
    end
  end

  def evaluate_with_llm_judge(original_prompt, response, eval_type)
    criteria = case eval_type
    when :check_repetition_strict
      <<~CRITERIA
        Evaluate for CONTENT QUALITY focusing on:
        1. Vocabulary diversity - does it use varied language or repeat phrases? (-3 for excessive repetition)
        2. No stuck/looping patterns - watch for same words repeated consecutively (-4 for loops)
        3. Clarity and coherence - is it well-written?
        4. Appropriate length and depth for the request
        5. No garbled/corrupted text (-3 for garbled)
      CRITERIA
    when :check_long_form_strict
      <<~CRITERIA
        Evaluate for LANDING PAGE / LONG-FORM CONTENT quality:
        1. Structure - proper sections with headers (H1, H2, H3) - (-2 if missing)
        2. Completeness - includes ALL requested elements (benefits, testimonials, CTA, tables, etc.)
        3. Formatting - tables, lists, code blocks where appropriate (-1 per missing element)
        4. Persuasive quality - compelling copy, not generic boilerplate
        5. Professional tone - polished, not repetitive or robotic
        6. Length - substantial (500+ words expected, -3 if too short)
        7. Markdown correctness - proper syntax
      CRITERIA
    when :check_reasoning_strict
      <<~CRITERIA
        Evaluate for REASONING & ANALYSIS quality:
        1. Calculations - if numbers given, are calculations shown AND CORRECT? (-3 for math errors)
        2. Logical structure - clear framework, step-by-step analysis
        3. Causal reasoning - shows cause and effect chains (at least 3 steps)
        4. Nuance - considers multiple perspectives, tradeoffs, counterarguments
        5. Clear conclusion - explicit recommendation with reasoning (-2 if missing)
        6. Depth - thorough analysis, not surface-level (-2 if shallow)
      CRITERIA
    else
      "Evaluate overall quality, clarity, and correctness."
    end

    judge_prompt = <<~PROMPT
      You are an expert evaluator. Rate the following AI response on a scale of 1-10.
      Be STRICT - a score of 10 should be rare and only for exceptional responses.
      Average responses should score 5-6. Good responses 7-8.

      ORIGINAL PROMPT:
      #{original_prompt}

      AI RESPONSE TO EVALUATE:
      #{response.to_s[0..6000]}

      EVALUATION CRITERIA:
      #{criteria}

      Respond in this EXACT JSON format (no other text):
      {"score": [1-10], "issues": ["issue1", "issue2"]}
      
      If no issues, use: {"score": X, "issues": []}
    PROMPT

    begin
      judge_response = @bedrock.send_message_converse(
        "You are a strict but fair evaluator. Output only valid JSON.",
        [{ role: "user", content: judge_prompt }],
        model: "claude-sonnet-4-5",  # Use Sonnet 4.5 as judge
        max_tokens: 300,
        temperature: 0.2
      )

      # Parse the JSON response
      judge_text = judge_response.to_s.strip
      
      # Extract JSON from response (handle markdown code blocks)
      json_match = judge_text.match(/\{[^}]+\}/m)
      
      if json_match
        result = JSON.parse(json_match[0])
        score = result["score"].to_i
        issues = result["issues"] || []
        
        { score: [[score, 10].min, 0].max, issues: issues }
      else
        # Fallback parsing
        score_match = judge_text.match(/score["']?\s*:\s*(\d+)/i)
        score = score_match ? score_match[1].to_i : 5
        { score: score, issues: ["LLM judge response format issue"] }
      end
    rescue => e
      # Fallback to pattern-based if LLM judge fails
      Rails.logger.warn "[Eval] LLM judge failed: #{e.message}, falling back to pattern"
      send(eval_type, response)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # EVALUATION METHODS
  # ═══════════════════════════════════════════════════════════════

  def check_repetition(response)
    text = response.to_s
    issues = []
    score = 10

    # Check for repeated phrases (3+ word sequences appearing multiple times)
    words = text.downcase.split(/\s+/)
    trigrams = words.each_cons(3).map { |trio| trio.join(' ') }
    trigram_counts = trigrams.tally
    repeated = trigram_counts.select { |_, count| count > 2 }
    
    if repeated.any?
      issues << "Repeated phrases: #{repeated.keys.first(3).join(', ')}"
      score -= [repeated.values.max * 2, 5].min
    end

    # Check for stuttering (same word repeated consecutively)
    stutters = text.scan(/\b(\w+)\s+\1\s+\1\b/i)
    if stutters.any?
      issues << "Word stuttering detected: #{stutters.flatten.first(3).join(', ')}"
      score -= 3
    end

    # Check for garbled characters
    if text.include?('�') || text.match?(/[\u{FFFD}]/)
      issues << "Contains replacement characters (encoding issues)"
      score -= 2
    end

    # Check for reasonable length
    if text.length < 50
      issues << "Response too short"
      score -= 2
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_long_form(response)
    text = response.to_s
    issues = []
    score = 10

    # Check minimum length for long-form content (should be substantial)
    if text.length < 500
      issues << "Too short for landing page content (#{text.length} chars)"
      score -= 3
    end

    # Check for repeated phrases more strictly (3+ word sequences appearing 3+ times)
    # Exclude markdown table syntax and common structural patterns
    words = text.downcase.split(/\s+/)
    trigrams = words.each_cons(3).map { |trio| trio.join(' ') }
    trigram_counts = trigrams.tally
    
    # Filter out legitimate patterns (table syntax, markdown separators, common structure)
    excluded_patterns = [
      %r{^\|\s*:?-+:?\s*\|$},              # Table separators like "| :--- |"
      %r{^-{3,}\s*##$},                    # Markdown --- ## patterns
      %r{^\*{2,}\w+\*{2,}$},               # Bold words
      %r{^#+\s*\*{2}}                      # Header + bold
    ]
    
    repeated = trigram_counts.select do |phrase, count| 
      count >= 3 && !excluded_patterns.any? { |p| phrase.match?(p) }
    end
    
    # Filter out structural repetitions that are expected in landing pages
    repeated.reject! { |phrase, _| phrase.include?(':---') || phrase.include?('---') }
    
    if repeated.any?
      issues << "Excessive phrase repetition: #{repeated.keys.first(3).join(', ')}"
      score -= [repeated.values.max, 4].min
    end

    # Check for "degenerate" patterns (word getting stuck)
    stuck_patterns = text.scan(/(\b\w+\b)(\s+\1){2,}/i)
    if stuck_patterns.any?
      issues << "Word stuck/looping: #{stuck_patterns.first.first}"
      score -= 4
    end

    # Check for proper structure (multiple sections)
    section_count = text.scan(/^#+\s/m).count
    if section_count < 3
      issues << "Lacks proper section structure (only #{section_count} headers)"
      score -= 2
    end

    # Check for garbled text patterns (excluding legitimate markdown)
    garbled_patterns = [
      /\*\s+of\s+\*/i,                    # Broken markdown like "* of *"
      /(\w{3,})\*\s*\1/i,                 # Word*word repetition (but not **bold**)
      /[\u{FFFD}]/,                       # Replacement char
      /\b([a-z])\1{5,}\b/i,               # Repeated letters (aaaaaa) - 6+ same letter
      /([^\s\-\*#|:`])\1{15,}/            # Any non-markdown char repeated 15+ times
    ]
    
    garbled_patterns.each do |pattern|
      if text.match?(pattern)
        match = text.match(pattern).to_s[0..30]
        issues << "Garbled/corrupted output: '#{match}'"
        score -= 3
        break
      end
    end
    
    # Check for degenerate markdown (excessive separators)
    separator_count = text.scan(/^---+$/m).count
    if separator_count > 10
      issues << "Excessive markdown separators (#{separator_count})"
      score -= 2
    end

    # Check for missing characters/typos pattern (e.g., "tothe" instead of "to the")
    common_typos = text.scan(/\b(tothe|ofthe|forthe|inthe|onthe|atthe)\b/i)
    if common_typos.length > 2
      issues << "Multiple word-joining typos: #{common_typos.flatten.uniq.join(', ')}"
      score -= 2
    end

    # Check for proper call-to-action (landing pages should have one)
    unless text.match?(/get started|sign up|learn more|contact us|try|start|begin|join/i)
      issues << "Missing call-to-action for landing page"
      score -= 1
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_markdown(response)
    text = response.to_s
    issues = []
    score = 10

    # Check for headers
    unless text.match?(/^#+\s/m)
      issues << "Missing markdown headers"
      score -= 2
    end

    # Check for proper bold/italic (not broken)
    broken_bold = text.scan(/\*\*[^*]{1,3}\*\*/).select { |m| m.length < 6 }
    if broken_bold.any?
      issues << "Potentially broken bold formatting"
      score -= 1
    end

    # Check for lists
    unless text.match?(/^[-*]\s/m) || text.match?(/^\d+\.\s/m)
      issues << "Missing bullet or numbered lists"
      score -= 2
    end

    # Check for code blocks if expected
    if text.include?('```')
      # Good - has code blocks
    end

    # Check for table if requested
    if text.match?(/\|.*\|.*\|/)
      # Good - has table structure
    end

    # Check for garbled text
    if text.match?(/\*\s*of\*\s*the\s*\*/i) || text.match?(/(\w+)\*\s*\1/i)
      issues << "Garbled markdown/text mixing"
      score -= 3
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_reasoning(response)
    text = response.to_s
    issues = []
    score = 10

    # Check for structured thinking - broader set of logical connectors
    logical_connectors = /\b(because|therefore|however|firstly|secondly|in conclusion|additionally|furthermore|consequently|as a result|on the other hand|meanwhile|although|while|since|thus|hence|accordingly|moreover|for example|for instance|specifically|in contrast|similarly|ultimately|overall)\b/i
    
    unless text.match?(logical_connectors)
      issues << "Lacks logical connectors"
      score -= 2
    end

    # Check for balanced analysis (pros/cons, multiple perspectives)
    has_multiple_points = text.split(/\n/).count { |line| line.match?(/^[-*\d•]/) } >= 3
    unless has_multiple_points
      issues << "May lack structured list points"
      score -= 1
    end

    # Check for analysis depth - should have substantial reasoning
    if text.length < 300
      issues << "Response too brief for thorough analysis"
      score -= 1
    end

    # Check for calculations only on the SaaS scenario prompt (contains MRR)
    if text.downcase.include?('mrr') || text.downcase.include?('monthly recurring')
      # Good - they addressed MRR
    elsif text.match?(/\$50.*arpu/i) || text.match?(/1000.*users/i)
      # This is the SaaS prompt - check if they did the math
      unless text.match?(/\$?\d{2,}[,\d]*\s*(mrr|monthly|revenue|=)/i)
        issues << "SaaS scenario: calculation expected but not clearly shown"
        score -= 1
      end
    end

    # Check for excessive repetition in reasoning (lighter penalty - some structure is expected)
    repetition_result = check_repetition(response)
    severe_repetition = repetition_result[:issues].any? { |i| i.include?("stuttering") || i.include?("encoding") }
    
    if severe_repetition
      issues.concat(repetition_result[:issues])
      score -= 2
    elsif repetition_result[:issues].any?
      # Only mention if there are real repetition issues, with lighter penalty
      issues << "Minor phrase repetition in analysis"
      score -= 1
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_code(response)
    text = response.to_s
    issues = []
    score = 10

    # Check for code blocks
    unless text.include?('```')
      issues << "Missing code block formatting"
      score -= 2
    end

    # Check for function/method definition
    unless text.match?(/\b(def|function|const|let|var|class)\b/)
      issues << "May not contain actual code"
      score -= 3
    end

    # Check for basic syntax elements
    unless text.match?(/[(){}\[\]]/) && text.match?(/[:;,]/)
      issues << "May have incomplete syntax"
      score -= 1
    end

    # Check for proper indentation (at least some indented lines)
    indented_lines = text.split("\n").count { |line| line.start_with?('  ') || line.start_with?("\t") }
    if indented_lines < 2
      issues << "May lack proper indentation"
      score -= 1
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_instructions(response)
    text = response.to_s.strip
    issues = []
    score = 10

    # Check for conciseness when expected
    if text.split("\n").length > 20
      issues << "Response may be too verbose"
      score -= 2
    end

    # Check for following simple constraints
    # (This is prompt-specific, so we do basic checks)
    
    # If asked for numbered items, check we got some
    numbered_items = text.scan(/^\d+[\.\)]\s/m).length
    
    # Check for unnecessary preamble
    if text.match?(/^(Sure|Of course|Certainly|Here|I'd be happy)/i)
      issues << "Unnecessary preamble"
      score -= 1
    end

    { score: [score, 0].max, issues: issues }
  end

  # ═══════════════════════════════════════════════════════════════
  # STRICT EVALUATION METHODS (Harder tests to differentiate models)
  # ═══════════════════════════════════════════════════════════════

  def check_repetition_strict(response)
    text = response.to_s
    issues = []
    score = 10

    # Minimum length for comprehensive content
    if text.length < 400
      issues << "Too short for comprehensive content (#{text.length} chars)"
      score -= 2
    end

    # Strict phrase repetition: 4-word sequences appearing 2+ times (excluding common phrases)
    words = text.downcase.gsub(/[^\w\s]/, ' ').split
    fourgrams = words.each_cons(4).map { |g| g.join(' ') }
    fourgram_counts = fourgrams.tally
    
    # Filter out common acceptable phrases
    common_phrases = ['in order to', 'as well as', 'on the other hand', 'at the same time']
    repeated = fourgram_counts.select { |phrase, count| count >= 2 && !common_phrases.include?(phrase) }
    
    if repeated.length > 3
      issues << "Multiple repeated 4-word phrases (#{repeated.length} unique)"
      score -= 3
    elsif repeated.any?
      issues << "Phrase repetition: '#{repeated.keys.first}'"
      score -= 1
    end

    # Check for vocabulary diversity (unique words / total words)
    unique_ratio = words.uniq.length.to_f / words.length
    if unique_ratio < 0.35
      issues << "Low vocabulary diversity (#{(unique_ratio * 100).round}% unique)"
      score -= 2
    elsif unique_ratio < 0.45
      issues << "Moderate vocabulary diversity (#{(unique_ratio * 100).round}% unique)"
      score -= 1
    end

    # Check for stuck patterns (same word 3+ times consecutively)
    if text.match?(/\b(\w+)\s+\1\s+\1\b/i)
      issues << "Word repetition loop detected"
      score -= 3
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_long_form_strict(response)
    text = response.to_s
    issues = []
    score = 10

    # Length requirement
    word_count = text.split.length
    if word_count < 500
      issues << "Too short: #{word_count} words (expected 500+)"
      score -= 3
    elsif word_count < 300
      issues << "Far too short: #{word_count} words"
      score -= 5
    end

    # Section structure - need multiple H2+ sections
    h2_count = text.scan(/^##[^#]/m).length
    h3_count = text.scan(/^###/m).length
    
    if h2_count < 3
      issues << "Insufficient sections (only #{h2_count} H2 headers)"
      score -= 2
    end
    
    if h3_count < 2
      issues << "Lacks subsection depth (only #{h3_count} H3 headers)"
      score -= 1
    end

    # Check for required elements based on prompts
    has_table = text.include?('|') && text.match?(/\|.*\|.*\|/)
    has_bullets = text.match?(/^[-*]\s/m)
    has_numbers = text.match?(/^\d+\.\s/m)
    
    missing_elements = []
    missing_elements << "table" unless has_table
    missing_elements << "bullet list" unless has_bullets
    missing_elements << "numbered list" unless has_numbers
    
    if missing_elements.length > 1
      issues << "Missing formatting: #{missing_elements.join(', ')}"
      score -= missing_elements.length
    end

    # Check for testimonial-like content (quotes)
    has_quotes = text.include?('"') || text.match?(/>.*—/)
    unless has_quotes
      issues << "Missing quotes/testimonials"
      score -= 1
    end

    # Apply repetition check
    rep_result = check_repetition_strict(response)
    if rep_result[:issues].any?
      issues << rep_result[:issues].first
      score -= 1
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_markdown_strict(response)
    text = response.to_s
    issues = []
    score = 10

    # Check for complete header hierarchy
    has_h1 = text.match?(/^# [^#]/m)
    has_h2 = text.match?(/^## [^#]/m)
    has_h3 = text.match?(/^### /m)
    
    unless has_h1
      issues << "Missing H1 header"
      score -= 1
    end
    
    unless has_h2
      issues << "Missing H2 headers"
      score -= 2
    end

    # Check for proper table structure
    table_rows = text.scan(/^\|.+\|$/m)
    if table_rows.length > 0
      # Check for header separator row
      unless table_rows.any? { |row| row.match?(/\|[\s:-]+\|/) }
        issues << "Table missing separator row"
        score -= 1
      end
      
      # Check for consistent columns
      col_counts = table_rows.map { |row| row.count('|') }
      unless col_counts.uniq.length == 1
        issues << "Inconsistent table columns"
        score -= 1
      end
    else
      issues << "Missing table"
      score -= 2
    end

    # Check for code elements
    has_inline_code = text.match?(/`[^`]+`/)
    has_code_block = text.include?('```')
    
    unless has_inline_code || has_code_block
      issues << "Missing code formatting"
      score -= 1
    end

    # Check for nested lists (indented bullets)
    has_nested = text.match?(/^  [-*]/m) || text.match?(/^\t[-*]/m)
    unless has_nested
      issues << "Missing nested list structure"
      score -= 1
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_reasoning_strict(response)
    text = response.to_s
    issues = []
    score = 10

    # Check for explicit calculations with numbers
    has_calculations = text.match?(/\d+\s*[×x*]\s*\d+/) ||  # multiplication
                       text.match?(/\d+\s*[÷\/]\s*\d+/) ||   # division
                       text.match?(/=\s*\$?[\d,]+/) ||       # equals result
                       text.match?(/\$[\d,]+\s*(mrr|arr|ltv|revenue)/i)
    
    # Check if this is a calculation prompt
    is_calc_prompt = text.downcase.include?('mrr') || text.downcase.include?('ltv') || text.downcase.include?('arpu')
    
    if is_calc_prompt && !has_calculations
      issues << "Calculation prompt but no clear math shown"
      score -= 2
    end

    # Check for structured framework/analysis
    has_framework = text.match?(/\b(framework|step \d|phase \d|consideration \d)\b/i) ||
                    text.scan(/^##/m).length >= 3
    
    unless has_framework
      issues << "Lacks structured framework"
      score -= 1
    end

    # Check for explicit recommendation/conclusion
    has_recommendation = text.match?(/\b(recommend|conclusion|verdict|therefore.*should|in summary.*best)\b/i)
    
    unless has_recommendation
      issues << "Missing clear recommendation/conclusion"
      score -= 1
    end

    # Check for causal reasoning (for cause/effect prompts)
    has_causal = text.match?(/\b(leads to|causes|results in|because|therefore|consequently|as a result)\b/i)
    causal_count = text.scan(/\b(leads to|causes|results in|→|->)\b/i).length
    
    if causal_count < 3
      issues << "Limited causal chain depth (#{causal_count} causal links)"
      score -= 1
    end

    # Check for nuance (considering multiple perspectives)
    has_nuance = text.match?(/\b(however|on the other hand|alternatively|but|conversely|that said)\b/i)
    
    unless has_nuance
      issues << "Lacks nuanced analysis (missing counterpoints)"
      score -= 1
    end

    # Word count for thorough analysis
    word_count = text.split.length
    if word_count < 250
      issues << "Too brief for thorough analysis (#{word_count} words)"
      score -= 2
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_code_strict(response)
    text = response.to_s
    issues = []
    score = 10

    # Must have code blocks
    code_blocks = text.scan(/```(\w+)?\n(.*?)```/m)
    
    if code_blocks.empty?
      issues << "No code blocks found"
      score -= 4
      return { score: [score, 0].max, issues: issues }
    end

    code_content = code_blocks.map { |b| b[1] }.join("\n")

    # Check for language-specific requirements
    if code_content.match?(/\bdef\b/) # Python
      # Type hints
      unless code_content.match?(/def\s+\w+\([^)]*:\s*\w+/)
        issues << "Python: Missing type hints"
        score -= 1
      end
      
      # Docstring
      unless code_content.match?(/""".*?"""/m) || code_content.match?(/'''.*?'''/m)
        issues << "Python: Missing docstring"
        score -= 1
      end
    end

    if code_content.match?(/function|const|let/) # JavaScript
      # Error handling
      unless code_content.match?(/try|catch|throw|if\s*\(.*?null|undefined/)
        issues << "JavaScript: Limited error handling"
        score -= 1
      end
    end

    if code_content.match?(/\bclass\b.*\bend\b/m) # Ruby
      # Initialize method
      unless code_content.match?(/def initialize/)
        issues << "Ruby class: Missing initialize method"
        score -= 1
      end
    end

    # Check for comments
    unless code_content.match?(/#[^!]|\/\/|\/\*/)
      issues << "Missing code comments"
      score -= 1
    end

    # Check for example usage
    unless text.match?(/example|usage|demo|test|output:/i)
      issues << "Missing example usage"
      score -= 1
    end

    # Minimum code complexity (lines)
    code_lines = code_content.split("\n").reject { |l| l.strip.empty? }.length
    if code_lines < 15
      issues << "Code too simple (#{code_lines} lines)"
      score -= 1
    end

    { score: [score, 0].max, issues: issues }
  end

  def check_instructions_strict(response)
    text = response.to_s.strip
    issues = []
    score = 10

    # Check for NO preamble at all
    if text.match?(/^(Sure|Of course|Certainly|Here|I('d| would| will)|Let me|Absolutely)/i)
      issues << "Unnecessary preamble (should start directly)"
      score -= 2
    end

    # Check for NO explanation after
    lines = text.split("\n").reject(&:empty?)
    last_lines = lines.last(2).join(' ')
    if last_lines.match?(/\b(note|hope|let me know|feel free|if you need)\b/i)
      issues << "Unnecessary closing/explanation"
      score -= 1
    end

    # For JSON prompt: validate JSON
    if text.include?('{') && text.include?('}')
      json_match = text.match(/\{[^}]+\}/m)
      if json_match
        begin
          json = JSON.parse(json_match[0])
          
          # Check specific fields if this is the JSON prompt
          if json.is_a?(Hash)
            if json['name'] && (json['name'].length < 5 || json['name'].length > 10)
              issues << "JSON 'name' field wrong length"
              score -= 1
            end
            if json['values'] && (!json['values'].is_a?(Array) || json['values'].length != 4)
              issues << "JSON 'values' should be array of 4"
              score -= 1
            end
          end
        rescue JSON::ParserError
          issues << "Invalid JSON syntax"
          score -= 3
        end
      end
    end

    # For numbered list prompt: check count
    numbered_items = text.scan(/^\d+[\.\)]\s/m).length
    if numbered_items > 0 && numbered_items != 7
      issues << "Wrong number of items (#{numbered_items}, expected 7)"
      score -= 2
    end

    # Check for format compliance (no extra content)
    if text.length > 500 && !text.include?('{')  # Not JSON
      issues << "Response too long for constrained prompt"
      score -= 1
    end

    { score: [score, 0].max, issues: issues }
  end

  # ═══════════════════════════════════════════════════════════════
  # REPORTING
  # ═══════════════════════════════════════════════════════════════

  def print_summary
    puts "\n" + "=" * 70
    puts "📊 EVALUATION SUMMARY"
    puts "=" * 70

    # Build comparison table
    puts "\n#{'Model'.ljust(20)} | " + TEST_CATEGORIES.keys.map { |k| k.to_s[0..8].center(10) }.join(" | ") + " | Overall"
    puts "-" * (25 + TEST_CATEGORIES.count * 13 + 10)

    overall_scores = {}
    
    @results.each do |model, categories|
      row = model.ljust(20) + " | "
      scores = []
      
      TEST_CATEGORIES.keys.each do |cat|
        score = categories.dig(cat, :score) || 0
        scores << score
        color = score >= 8 ? "\e[32m" : (score >= 5 ? "\e[33m" : "\e[31m")
        row += "#{color}#{score.to_s.center(10)}\e[0m | "
      end
      
      overall = (scores.sum / scores.length.to_f).round(1)
      overall_scores[model] = overall
      overall_color = overall >= 8 ? "\e[32m" : (overall >= 5 ? "\e[33m" : "\e[31m")
      row += "#{overall_color}#{overall}\e[0m"
      
      puts row
    end

    # Print recommendations
    puts "\n" + "-" * 70
    puts "📋 RECOMMENDATIONS"
    puts "-" * 70

    best_overall = overall_scores.max_by { |_, v| v }
    puts "🏆 Best Overall: #{best_overall[0]} (#{best_overall[1]}/10)"

    TEST_CATEGORIES.each do |cat, config|
      best = @results.max_by { |_, v| v.dig(cat, :score) || 0 }
      score = best[1].dig(cat, :score) || 0
      puts "   #{config[:name]}: #{best[0]} (#{score}/10)"
    end

    puts "\n" + "=" * 70
  end

  def save_results
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = Rails.root.join("tmp", "model_evaluation_#{timestamp}.json")
    
    File.write(filename, JSON.pretty_generate({
      timestamp: Time.current.iso8601,
      mode: @mode,
      models_tested: models_to_test,
      results: @results
    }))
    
    puts "📁 Results saved to: #{filename}"
  end

  def create_test_entity
    Entity.create!(
      name: "Model Evaluation Test Entity",
      slug: "model-eval-test",
      company_type: "test"
    )
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# TOOL USAGE EVALUATOR - Tests models' ability to use tools correctly
# ═══════════════════════════════════════════════════════════════════════════════

class ToolUsageEvaluator
  # Models to test for tool usage
  TOOL_MODELS = %w[
    claude-sonnet-4-5
    deepseek-v3
    deepseek-r1
    mistral-large-3
    qwen-3-32b
  ].freeze

  # Simple tools for testing
  TEST_TOOLS = [
    {
      name: "get_weather",
      description: "Get the current weather for a location",
      input_schema: {
        type: "object",
        properties: {
          location: { type: "string", description: "City name" },
          units: { type: "string", enum: ["celsius", "fahrenheit"], description: "Temperature units" }
        },
        required: ["location"]
      }
    },
    {
      name: "calculate",
      description: "Perform a mathematical calculation",
      input_schema: {
        type: "object",
        properties: {
          expression: { type: "string", description: "Math expression to evaluate" }
        },
        required: ["expression"]
      }
    },
    {
      name: "search_database",
      description: "Search for records in the database",
      input_schema: {
        type: "object",
        properties: {
          query: { type: "string", description: "Search query" },
          limit: { type: "integer", description: "Max results to return" },
          filters: { 
            type: "object", 
            description: "Optional filters",
            properties: {
              status: { type: "string" },
              created_after: { type: "string", description: "ISO date" }
            }
          }
        },
        required: ["query"]
      }
    }
  ].freeze

  # Test scenarios
  TOOL_TESTS = {
    simple_single_tool: {
      name: "Simple Single Tool Call",
      prompt: "What's the weather in New York?",
      expected_tool: "get_weather",
      expected_args: ["location"]
    },
    tool_with_options: {
      name: "Tool with Optional Args",
      prompt: "What's the temperature in London in Celsius?",
      expected_tool: "get_weather",
      expected_args: ["location", "units"]
    },
    calculation: {
      name: "Calculation Tool",
      prompt: "Calculate 15% of 249.99",
      expected_tool: "calculate",
      expected_args: ["expression"]
    },
    complex_query: {
      name: "Complex Tool with Nested Args",
      prompt: "Search for active customers created after January 1st 2025, limit to 10 results",
      expected_tool: "search_database",
      expected_args: ["query", "limit", "filters"]
    },
    no_tool_needed: {
      name: "Should NOT Use Tool",
      prompt: "What is the capital of France?",
      expected_tool: nil,  # Should answer directly
      expected_args: []
    },
    multi_step: {
      name: "Multi-Step Reasoning",
      prompt: "I need to plan a trip to Tokyo. First, what's the weather there?",
      expected_tool: "get_weather",
      expected_args: ["location"]
    }
  }.freeze

  def initialize(mode: 'full')
    @mode = mode
    @results = {}
    @entity = Entity.first || create_test_entity
    @bedrock = BedrockService.new(entity: @entity)
  end

  def run
    puts "\n" + "=" * 70
    puts "🔧 TOOL USAGE BENCHMARK"
    puts "=" * 70
    puts "Mode: #{@mode}"
    puts "Models: #{TOOL_MODELS.join(', ')}"
    puts "Tests: #{TOOL_TESTS.keys.join(', ')}"
    puts "=" * 70

    TOOL_MODELS.each do |model|
      test_model_tools(model)
    end

    print_summary
    save_results
  end

  private

  def test_model_tools(model)
    puts "\n" + "-" * 50
    puts "Testing: #{model}"
    puts "-" * 50

    @results[model] = {}
    tests = @mode == 'quick' ? TOOL_TESTS.first(2).to_h : TOOL_TESTS

    tests.each do |test_key, test_config|
      print "  #{test_config[:name]}... "
      
      result = run_tool_test(model, test_config)
      @results[model][test_key] = result

      if result[:success]
        puts "✅ (#{result[:latency_ms]}ms)"
        if result[:notes].any?
          result[:notes].each { |note| puts "      ℹ️  #{note}" }
        end
      else
        puts "❌ (#{result[:latency_ms]}ms)"
        result[:issues].each { |issue| puts "      ⚠️  #{issue}" }
      end
    end
  end

  def run_tool_test(model, test_config)
    start_time = Time.current
    issues = []
    notes = []
    
    begin
      # Use raw converse API to see if model WANTS to use tools (without auto-executing)
      result = call_model_for_tool_check(model, test_config[:prompt])
      
      latency_ms = ((Time.current - start_time) * 1000).round
      
      if result[:error]
        return {
          success: false,
          latency_ms: latency_ms,
          tool_called: false,
          issues: [result[:error]],
          notes: [],
          response_preview: ""
        }
      end
      
      tool_called = result[:tool_use]
      response_text = result[:text] || ""
      
      if test_config[:expected_tool].nil?
        # Should NOT have called a tool
        if tool_called
          issues << "Called tool '#{tool_called[:name]}' when direct answer expected"
          success = false
        else
          success = true
          notes << "Correctly answered without tools"
        end
      else
        # Should have called the expected tool
        if !tool_called
          # Check if it output fake tool calls (common issue)
          if response_text.match?(/<function=|<tool>|\[Called\s+\w+|```json.*tool/)
            issues << "Output fake tool call syntax instead of using native tool API"
          else
            issues << "Did not call any tool - answered directly instead"
          end
          success = false
        elsif tool_called[:name] != test_config[:expected_tool]
          issues << "Called '#{tool_called[:name]}' instead of '#{test_config[:expected_tool]}'"
          success = false
        else
          # Check arguments
          arg_keys = tool_called[:input]&.keys&.map(&:to_s) || []
          missing_args = test_config[:expected_args] - arg_keys
          if missing_args.any? && missing_args != test_config[:expected_args]
            notes << "Missing optional args: #{missing_args.join(', ')}"
          end
          success = true
          notes << "Correctly called #{tool_called[:name]} with args: #{arg_keys.join(', ')}"
        end
      end

      {
        success: success,
        latency_ms: latency_ms,
        tool_called: !!tool_called,
        tool_name: tool_called&.dig(:name),
        tool_args: tool_called&.dig(:input),
        issues: issues,
        notes: notes,
        response_preview: response_text[0..200]
      }
    rescue => e
      {
        success: false,
        latency_ms: ((Time.current - start_time) * 1000).round,
        tool_called: false,
        issues: ["Error: #{e.message}"],
        notes: [],
        response_preview: ""
      }
    end
  end

  def call_model_for_tool_check(model, prompt)
    # Get the model ID
    model_id = case model
    when "claude-sonnet-4-5" then "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
    when "deepseek-v3" then "deepseek.v3-v1:0"
    when "deepseek-r1" then "us.deepseek.r1-v1:0"
    when "mistral-large-3" then "mistral.mistral-large-3-675b-instruct"
    when "qwen-3-32b" then "qwen.qwen3-32b-v1:0"
    else model
    end
    
    # Get appropriate client (some models need specific regions)
    client = if model.start_with?("deepseek")
      Aws::BedrockRuntime::Client.new(region: 'us-east-2')
    else
      Aws::BedrockRuntime::Client.new(region: ENV.fetch('AWS_REGION', 'us-east-1'))
    end
    
    # Format tools for Bedrock
    formatted_tools = TEST_TOOLS.map do |tool|
      {
        tool_spec: {
          name: tool[:name],
          description: tool[:description],
          input_schema: { json: tool[:input_schema] }
        }
      }
    end
    
    payload = {
      model_id: model_id,
      messages: [
        { role: "user", content: [{ text: prompt }] }
      ],
      system: [{ text: "You are a helpful assistant with access to tools. Use tools when they would help answer the user's question. If you can answer directly without a tool, do so." }],
      inference_config: {
        max_tokens: 1000,
        temperature: 0.3
      },
      tool_config: {
        tools: formatted_tools,
        tool_choice: { auto: {} }
      }
    }
    
    response = client.converse(payload)
    
    # Check the response for tool_use blocks
    tool_use = nil
    text_content = ""
    
    response.output.message.content.each do |block|
      if block.respond_to?(:tool_use) && block.tool_use
        tool_use = {
          name: block.tool_use.name,
          input: block.tool_use.input.to_h
        }
      elsif block.respond_to?(:text) && block.text
        text_content += block.text
      end
    end
    
    { tool_use: tool_use, text: text_content, stop_reason: response.stop_reason }
  rescue Aws::BedrockRuntime::Errors::ServiceError => e
    { error: "Bedrock error: #{e.message}" }
  rescue => e
    { error: "Unexpected error: #{e.message}" }
  end

  def print_summary
    puts "\n" + "=" * 70
    puts "📊 TOOL USAGE SUMMARY"
    puts "=" * 70

    # Calculate scores
    scores = {}
    @results.each do |model, tests|
      passed = tests.values.count { |t| t[:success] }
      total = tests.length
      scores[model] = {
        passed: passed,
        total: total,
        percentage: (passed.to_f / total * 100).round(1),
        avg_latency: (tests.values.map { |t| t[:latency_ms] }.sum / total.to_f).round
      }
    end

    # Print table
    puts "\nModel                | Passed | Score  | Avg Latency"
    puts "-" * 60
    scores.sort_by { |_, s| -s[:percentage] }.each do |model, score|
      status = score[:percentage] >= 80 ? "✅" : score[:percentage] >= 50 ? "⚠️" : "❌"
      puts "#{model.ljust(20)} | #{score[:passed]}/#{score[:total]}    | #{score[:percentage]}%  | #{score[:avg_latency]}ms #{status}"
    end

    # Recommendations
    puts "\n" + "-" * 70
    puts "📋 TOOL USAGE RECOMMENDATIONS"
    puts "-" * 70
    
    best = scores.max_by { |_, s| s[:percentage] }
    fastest = scores.min_by { |_, s| s[:avg_latency] }
    
    puts "🏆 Best Tool Handler: #{best[0]} (#{best[1][:percentage]}% success)"
    puts "⚡ Fastest: #{fastest[0]} (#{fastest[1][:avg_latency]}ms avg)"
    
    # Flag problematic models
    scores.each do |model, score|
      if score[:percentage] < 50
        puts "❌ AVOID for tools: #{model} (only #{score[:percentage]}% success)"
      end
    end
  end

  def save_results
    filename = Rails.root.join("tmp", "tool_evaluation_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json")
    File.write(filename, JSON.pretty_generate({
      timestamp: Time.current.iso8601,
      mode: @mode,
      results: @results
    }))
    puts "\n📁 Results saved to: #{filename}"
  end

  def create_test_entity
    Entity.create!(
      name: "Tool Eval Test Entity",
      slug: "tool-eval-test",
      company_type: "test"
    )
  end
end
