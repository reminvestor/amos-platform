# frozen_string_literal: true

module Collaboration
  class PublicBenchmarks
    # ============================================
    # GSM8K - Grade School Math Word Problems
    # Tests: Multi-step reasoning, knowing when to ask for help
    # Source: https://github.com/openai/grade-school-math
    # ============================================
    GSM8K_SAMPLES = [
      {
        id: 'gsm8k_001',
        question: "Janet's ducks lay 16 eggs per day. She eats three for breakfast every morning and bakes muffins for her friends every day with four. She sells the remainder at the farmers' market daily for $2 per fresh duck egg. How much in dollars does she make every day at the farmers' market?",
        answer: '18',
        reasoning: '16 - 3 - 4 = 9 eggs remaining. 9 * $2 = $18',
        difficulty: 'easy',
        requires_tools: false
      },
      {
        id: 'gsm8k_002',
        question: "A robe takes 2 bolts of blue fiber and half that much white fiber. How many bolts in total does it take?",
        answer: '3',
        reasoning: '2 blue + 1 white (half of 2) = 3 bolts',
        difficulty: 'easy',
        requires_tools: false
      },
      {
        id: 'gsm8k_003',
        question: "Josh decides to try flipping a house. He buys a house for $80,000 and then puts in $50,000 in repairs. This increased the value of the house by 150%. How much profit did he make?",
        answer: '70000',
        reasoning: 'Original: $80,000. After repairs value = $80,000 * 2.5 = $200,000. Profit = $200,000 - $80,000 - $50,000 = $70,000',
        difficulty: 'medium',
        requires_tools: false
      },
      {
        id: 'gsm8k_004',
        question: "James writes a 3-page letter to 2 different friends twice a week. How many pages does he write a year?",
        answer: '624',
        reasoning: '3 pages * 2 friends * 2 times/week * 52 weeks = 624 pages',
        difficulty: 'medium',
        requires_tools: false
      },
      {
        id: 'gsm8k_005',
        question: "Weng earns $12 an hour for babysitting. Yesterday, she just did 50 minutes of babysitting. How much did she earn?",
        answer: '10',
        reasoning: '50 minutes = 50/60 hours = 5/6 hour. $12 * 5/6 = $10',
        difficulty: 'easy',
        requires_tools: false
      },
      {
        id: 'gsm8k_006',
        question: "Betty is saving money for a new wallet which costs $100. Betty has only half of the money she needs. Her parents decided to give her $15 for that purpose, and her grandparents twice as much as her parents. How much more money does Betty need to buy the wallet?",
        answer: '5',
        reasoning: 'Betty has $50. Parents give $15. Grandparents give $30. Total: $50 + $15 + $30 = $95. Needs $100 - $95 = $5 more.',
        difficulty: 'medium',
        requires_tools: false
      },
      {
        id: 'gsm8k_007',
        question: "A merchant wants to make a choice of purchase between 2 purchase plans: jewelry worth $5,000 or electronic gadgets worth $8,000. His financial advisor speculates that the jewelry market will go up 2.5% while the electronic gadgets market will rise 1.2% within the same month. If the merchant is looking to maximize profit at the end of this month by making a choice, how much profit would this be?",
        answer: '125',
        reasoning: 'Jewelry profit: $5,000 * 2.5% = $125. Electronics profit: $8,000 * 1.2% = $96. Max is $125.',
        difficulty: 'medium',
        requires_tools: false
      },
      {
        id: 'gsm8k_008',
        question: "Two trains leave San Rafael at the same time. They begin traveling westward, both traveling for 80 miles. The next day, they travel northward. The first train travels 150 miles north, while the second train travels 200 miles north. What is the combined distance the two trains travel?",
        answer: '510',
        reasoning: 'Train 1: 80 + 150 = 230 miles. Train 2: 80 + 200 = 280 miles. Combined: 230 + 280 = 510 miles.',
        difficulty: 'easy',
        requires_tools: false
      }
    ].freeze

    # ============================================
    # HotpotQA-style Multi-hop Questions
    # Tests: When to delegate, information synthesis
    # ============================================
    HOTPOT_SAMPLES = [
      {
        id: 'hotpot_001',
        question: "What is the capital of the country where the Eiffel Tower is located?",
        answer: 'Paris',
        reasoning: 'Eiffel Tower is in France. Capital of France is Paris.',
        difficulty: 'easy',
        requires_tools: true,
        tool_hint: 'web_search or knowledge lookup'
      },
      {
        id: 'hotpot_002',
        question: "Who was the president of the United States when the iPhone was first released?",
        answer: 'George W. Bush',
        reasoning: 'iPhone released June 2007. George W. Bush was president 2001-2009.',
        difficulty: 'medium',
        requires_tools: true,
        tool_hint: 'web_search'
      },
      {
        id: 'hotpot_003',
        question: "What is the population of the city where Microsoft is headquartered?",
        answer: 'approximately 150000',  # Redmond, WA
        reasoning: 'Microsoft HQ is in Redmond, WA. Population ~150,000.',
        difficulty: 'medium',
        requires_tools: true,
        tool_hint: 'web_search'
      },
      {
        id: 'hotpot_004',
        question: "In what year was the founder of Amazon born?",
        answer: '1964',
        reasoning: 'Jeff Bezos founded Amazon. He was born January 12, 1964.',
        difficulty: 'easy',
        requires_tools: true,
        tool_hint: 'web_search'
      },
      {
        id: 'hotpot_005',
        question: "What is the currency used in the country that hosted the 2020 Summer Olympics?",
        answer: 'Yen',
        reasoning: '2020 Olympics were in Tokyo, Japan. Japan uses the Yen.',
        difficulty: 'medium',
        requires_tools: true,
        tool_hint: 'web_search'
      }
    ].freeze

    # ============================================
    # Tool Use Tasks
    # Tests: Proper tool selection and execution
    # ============================================
    TOOL_USE_SAMPLES = [
      {
        id: 'tool_001',
        question: "What is the current temperature in New York City?",
        answer: :dynamic,  # Verify it's a reasonable temperature
        validation: ->(answer) { 
          temp = answer.to_s.scan(/[-]?\d+/).first&.to_i
          temp && temp.between?(-20, 120)  # Reasonable F range
        },
        difficulty: 'easy',
        requires_tools: true,
        expected_tool: 'weather'
      },
      {
        id: 'tool_002',
        question: "Search the web for the latest news about artificial intelligence and summarize the top result.",
        answer: :dynamic,
        validation: ->(answer) { answer.to_s.length > 50 },  # Should have substantive content
        difficulty: 'medium',
        requires_tools: true,
        expected_tool: 'web_search'
      },
      {
        id: 'tool_003',
        question: "Calculate the monthly payment for a $300,000 mortgage at 6.5% interest over 30 years.",
        answer: '1896',  # Approximately $1,896/month
        reasoning: 'Using mortgage formula: M = P[r(1+r)^n]/[(1+r)^n-1]',
        difficulty: 'hard',
        requires_tools: false,  # Can be calculated
        tolerance: 50  # Allow $50 variance
      }
    ].freeze

    # ============================================
    # Collaboration-Specific Tasks
    # Tests: When agents should ask for help
    # ============================================
    COLLABORATION_SAMPLES = [
      {
        id: 'collab_001',
        question: "I need to analyze this marketing campaign's performance and also get the current weather for our outdoor event in Chicago. Please handle both.",
        answer: :multi_task,
        validation: ->(answer, context) {
          # Should have both campaign analysis AND weather info
          answer.to_s.downcase.include?('campaign') && 
          (answer.to_s.downcase.include?('weather') || answer.to_s.downcase.include?('chicago'))
        },
        difficulty: 'hard',
        requires_collaboration: true,
        expected_agents: ['content_quality_analyzer', 'weather_scout']
      },
      {
        id: 'collab_002',
        question: "Research the top 3 competitors in the CRM software market and create a comparison table.",
        answer: :dynamic,
        validation: ->(answer) {
          # Should mention multiple CRM companies
          competitors = ['salesforce', 'hubspot', 'zoho', 'pipedrive', 'microsoft dynamics']
          competitors.count { |c| answer.to_s.downcase.include?(c) } >= 2
        },
        difficulty: 'hard',
        requires_collaboration: true,
        expected_agents: ['web_research_specialist']
      },
      {
        id: 'collab_003',
        question: "I'm a weather agent. I need help understanding how to format a JSON response. What's the best practice?",
        answer: :dynamic,
        validation: ->(answer) {
          answer.to_s.downcase.include?('json') && answer.to_s.length > 100
        },
        difficulty: 'easy',
        requires_collaboration: true,
        collaboration_type: 'advice'
      }
    ].freeze

    # ============================================
    # API
    # ============================================

    def self.all_benchmarks
      {
        gsm8k: GSM8K_SAMPLES,
        hotpot: HOTPOT_SAMPLES,
        tool_use: TOOL_USE_SAMPLES,
        collaboration: COLLABORATION_SAMPLES
      }
    end

    def self.get_benchmark(category)
      all_benchmarks[category.to_sym] || []
    end

    def self.get_by_difficulty(difficulty)
      all_benchmarks.values.flatten.select { |b| b[:difficulty] == difficulty.to_s }
    end

    def self.get_requiring_tools
      all_benchmarks.values.flatten.select { |b| b[:requires_tools] }
    end

    def self.get_requiring_collaboration
      all_benchmarks.values.flatten.select { |b| b[:requires_collaboration] }
    end

    def self.total_count
      all_benchmarks.values.flatten.size
    end

    def self.summary
      {
        total: total_count,
        by_category: all_benchmarks.transform_values(&:size),
        by_difficulty: {
          easy: get_by_difficulty('easy').size,
          medium: get_by_difficulty('medium').size,
          hard: get_by_difficulty('hard').size
        },
        requiring_tools: get_requiring_tools.size,
        requiring_collaboration: get_requiring_collaboration.size
      }
    end

    # Validate an answer against a benchmark
    def self.validate_answer(benchmark, answer, context = {})
      expected = benchmark[:answer]

      # Dynamic validation
      if expected == :dynamic || expected == :multi_task
        validator = benchmark[:validation]
        if validator
          # Handle validators with different arities (1 or 2 args)
          if validator.arity == 1
            return validator.call(answer)
          else
            return validator.call(answer, context)
          end
        end
        return answer.present?
      end

      # Numeric with tolerance - check ALL numbers in the answer
      if benchmark[:tolerance]
        # Extract all numbers from answer (handling $1,234.56 format)
        answer_nums = answer.to_s.gsub(',', '').scan(/[-]?\d+\.?\d*/).map(&:to_f).reject(&:zero?)
        expected_num = expected.to_f
        # Return true if ANY number in the answer matches within tolerance
        return true if answer_nums.any? { |n| (n - expected_num).abs <= benchmark[:tolerance] }
      end

      # String matching
      answer_str = answer.to_s.downcase.gsub(/[^a-z0-9\s]/, '').strip
      expected_str = expected.to_s.downcase.gsub(/[^a-z0-9\s]/, '').strip

      # Exact match
      return true if answer_str.include?(expected_str)

      # Numeric extraction and comparison
      answer_nums = answer_str.scan(/\d+/).map(&:to_i)
      expected_nums = expected_str.scan(/\d+/).map(&:to_i)
      
      return true if expected_nums.any? && expected_nums.all? { |n| answer_nums.include?(n) }

      false
    end
  end
end

