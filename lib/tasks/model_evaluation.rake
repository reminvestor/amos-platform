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
  # Models to test
  MODELS_TO_TEST = %w[
    deepseek-v3
    deepseek-r1
    mistral-large-3
    qwen-3-32b
    nemotron-nano-9b
  ].freeze

  # Test categories with prompts
  TEST_CATEGORIES = {
    content_quality: {
      name: "Content Quality (No Repetition)",
      prompts: [
        "Write a 3-paragraph introduction about artificial intelligence in business. Focus on clarity and avoid repetition.",
        "Describe the benefits of cloud computing in exactly 5 bullet points. Be concise and clear.",
        "Explain machine learning to a 10-year-old in 100 words or less."
      ],
      evaluation: :check_repetition
    },
    markdown_formatting: {
      name: "Markdown Formatting",
      prompts: [
        "Create a formatted document with: a title, 3 sections with headers, a bullet list, and a numbered list. Use proper markdown.",
        "Write a comparison table with 3 columns and 4 rows comparing Python, JavaScript, and Ruby.",
        "Create a well-formatted FAQ with 3 questions and answers using proper markdown headers and formatting."
      ],
      evaluation: :check_markdown
    },
    reasoning: {
      name: "Reasoning & Analysis",
      prompts: [
        "What are the pros and cons of remote work? List at least 3 of each with brief explanations.",
        "A company has $100,000 to invest. Compare investing in marketing vs. R&D. What factors should they consider?",
        "Analyze this business scenario: A SaaS startup has 1000 users, 5% monthly churn, and $50 ARPU. Calculate MRR and explain how to reduce churn."
      ],
      evaluation: :check_reasoning
    },
    code_generation: {
      name: "Code Generation",
      prompts: [
        "Write a Python function that calculates the factorial of a number using recursion.",
        "Create a simple HTML page with CSS that displays a centered card with a title and description.",
        "Write a JavaScript function that takes an array of numbers and returns the sum, average, min, and max."
      ],
      evaluation: :check_code
    },
    instruction_following: {
      name: "Instruction Following",
      prompts: [
        "List exactly 5 popular programming languages. No more, no less. Just the names, one per line.",
        "Write a haiku about technology. It must follow the 5-7-5 syllable structure exactly.",
        "Answer with only YES or NO: Is Python an interpreted language?"
      ],
      evaluation: :check_instructions
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

  def test_model(model, prompt, evaluation_method)
    start_time = Time.current
    
    begin
      # Format as simple messages array - the method handles conversion
      messages = [
        { role: "user", content: prompt }
      ]
      system_prompt = "You are a helpful AI assistant. Follow instructions carefully and provide high-quality responses."
      
      response = @bedrock.send_message_converse(
        system_prompt,
        messages,
        model: model,
        max_tokens: 2000,
        temperature: 0.7
      )
      
      latency_ms = ((Time.current - start_time) * 1000).round
      
      # Run evaluation
      evaluation = send(evaluation_method, response)
      
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

    # Check for structured thinking
    unless text.match?(/\b(because|therefore|however|firstly|secondly|in conclusion)\b/i)
      issues << "Lacks logical connectors"
      score -= 2
    end

    # Check for balanced analysis (pros/cons, multiple perspectives)
    has_multiple_points = text.split(/\n/).count { |line| line.match?(/^[-*\d]/) } >= 2
    unless has_multiple_points
      issues << "May lack multiple perspectives"
      score -= 1
    end

    # Check for calculations if numeric
    if text.match?(/\$?\d+[,\d]*/) && !text.match?(/=|total|sum|result/i)
      issues << "Contains numbers but may lack calculations"
      score -= 1
    end

    # Check for repetition in reasoning
    repetition_result = check_repetition(response)
    if repetition_result[:issues].any?
      issues.concat(repetition_result[:issues])
      score -= 2
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

