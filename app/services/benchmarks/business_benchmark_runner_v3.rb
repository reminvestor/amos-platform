# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Business Benchmark Runner v3.0
  # Multi-Dimensional Scoring & Verification
  # ============================================
  class BusinessBenchmarkRunnerV3
    attr_reader :entity, :user, :results, :run_id

    # Minimum expectations per tier (% of max score)
    TIER_EXPECTATIONS = {
      tier_1: 0.95,  # Easy: expect 95%
      tier_2: 0.85,  # Medium: expect 85%
      tier_3: 0.70,  # Hard: expect 70%
      tier_4: 0.50,  # Expert: expect 50%
      tier_5: 0.30   # Extreme: expect 30%
    }.freeze

    def initialize(entity: nil, user: nil, use_test_env: true)
      if use_test_env || (entity.nil? && user.nil?)
        @entity = TestEnvironment.entity
        @user = TestEnvironment.user
        @using_test_env = true
      else
        @entity = entity
        @user = user
        @using_test_env = false
      end

      @results = []
      @run_id = SecureRandom.uuid
      @scout = nil
    end

    # ============================================
    # MAIN EXECUTION METHODS
    # ============================================

    def run_tier(tier, progress_callback: nil)
      tasks = BusinessBenchmarkV3.tasks_by_tier(tier)
      run_tasks(tasks, progress_callback: progress_callback)
    end

    def run_category(category, progress_callback: nil)
      tasks = BusinessBenchmarkV3.tasks_by_category(category)
      run_tasks(tasks, progress_callback: progress_callback)
    end

    def run_single(task_id)
      task = BusinessBenchmarkV3.task(task_id)
      return nil unless task

      run_task(task)
    end

    def run_full_benchmark(progress_callback: nil)
      puts "\n" + "=" * 80
      puts "🏢 BUSINESS OPERATIONS BENCHMARK (BOB) v3.0 - HARD MODE"
      puts "=" * 80
      puts "Total tasks: #{BusinessBenchmarkV3.total_tasks}"
      puts "Difficulty breakdown: #{BusinessBenchmarkV3.difficulty_breakdown}"
      puts "=" * 80
      puts ""

      BusinessBenchmarkV3::DIFFICULTY_TIERS.each do |tier_key, tier_info|
        tasks = BusinessBenchmarkV3.tasks_by_tier(tier_key)
        next if tasks.empty?

        puts "📊 #{tier_info[:name]} (Tier #{tier_key.to_s.split('_').last})"
        puts "   Expected: #{(TIER_EXPECTATIONS[tier_key] * 100).round}%+ success"
        puts "-" * 40

        tasks.each_with_index do |task, idx|
          progress_callback&.call(tier_key, idx + 1, tasks.size, task[:name])
          
          print "  #{idx + 1}. #{task[:name].truncate(45)}... "
          
          result = run_task(task)
          @results << result

          status = result[:passed] ? "✓" : "✗"
          score_pct = (result[:total_score] * 100).round
          latency = result[:latency_ms]
          
          puts "#{status} (#{score_pct}%, #{latency}ms)"
          
          sleep(0.3)
        end
        puts ""
      end

      generate_report
    end

    def run_quick_benchmark(tasks_per_tier: 2, progress_callback: nil)
      puts "\n⚡ QUICK BOB v3.0 BENCHMARK"
      puts "=" * 50

      BusinessBenchmarkV3::DIFFICULTY_TIERS.each do |tier_key, tier_info|
        tasks = BusinessBenchmarkV3.tasks_by_tier(tier_key).sample(tasks_per_tier)
        next if tasks.empty?

        puts "#{tier_info[:name]}:"
        tasks.each do |task|
          result = run_task(task)
          @results << result
          status = result[:passed] ? "✓" : "✗"
          puts "  #{status} #{task[:name]} (#{(result[:total_score] * 100).round}%)"
        end
      end
      puts ""

      generate_report
    end

    # ============================================
    # TASK EXECUTION
    # ============================================

    def run_task(task)
      start_time = Time.current

      # Run setup if provided
      if task[:setup].is_a?(Proc)
        begin
          task[:setup].call(self)
        rescue => e
          Rails.logger.warn "[BOB v3] Setup failed for #{task[:id]}: #{e.message}"
        end
      end

      begin
        # Execute the task
        execution_result = execute_task(task)

        latency_ms = ((Time.current - start_time) * 1000).round

        # Score each dimension
        dimension_scores = score_dimensions(task, execution_result, latency_ms)

        # Calculate weighted total
        total_score = calculate_total_score(dimension_scores)

        # Determine pass/fail based on tier expectations
        tier_threshold = TIER_EXPECTATIONS[task[:tier]] * 0.8  # 80% of expectation
        passed = total_score >= tier_threshold

        result = {
          task_id: task[:id],
          tier: task[:tier],
          category: task[:category],
          name: task[:name],
          passed: passed,
          total_score: total_score,
          dimension_scores: dimension_scores,
          latency_ms: latency_ms,
          tool_calls: execution_result[:tool_calls],
          tools_used: execution_result[:tools_used],
          agents_used: execution_result[:agents_used],
          response: execution_result[:response],
          ground_truth_match: execution_result[:ground_truth_match],
          verification_details: execution_result[:verification_details],
          errors: execution_result[:errors]
        }

        # Cleanup if provided
        if task[:cleanup].is_a?(Proc)
          begin
            task[:cleanup].call(self)
          rescue => e
            Rails.logger.warn "[BOB v3] Cleanup failed for #{task[:id]}: #{e.message}"
          end
        end

        result
      rescue => e
        Rails.logger.error "[BOB v3] Task #{task[:id]} failed: #{e.message}"
        {
          task_id: task[:id],
          tier: task[:tier],
          category: task[:category],
          name: task[:name],
          passed: false,
          total_score: 0.0,
          dimension_scores: {},
          latency_ms: ((Time.current - start_time) * 1000).round,
          errors: [e.message]
        }
      end
    end

    # ============================================
    # SCORING
    # ============================================

    def score_dimensions(task, execution_result, latency_ms)
      scores = {}

      # Correctness (0.0 to 1.0)
      scores[:correctness] = score_correctness(task, execution_result)

      # Completeness (0.0 to 1.0)
      scores[:completeness] = score_completeness(task, execution_result)

      # Efficiency (0.0 to 1.0)
      scores[:efficiency] = score_efficiency(task, execution_result, latency_ms)

      # Groundedness (0.0 to 1.0)
      scores[:groundedness] = score_groundedness(task, execution_result)

      # Robustness (0.0 to 1.0)
      scores[:robustness] = score_robustness(task, execution_result)

      # Recovery (0.0 to 1.0)
      scores[:recovery] = score_recovery(task, execution_result)

      scores
    end

    def calculate_total_score(dimension_scores)
      total = 0.0

      BusinessBenchmarkV3::SCORING_DIMENSIONS.each do |dim, config|
        score = dimension_scores[dim] || 0.0
        weight = config[:weight]
        total += score * weight
      end

      total.round(4)
    end

    def score_correctness(task, result)
      return 0.0 if result[:errors]&.any?

      case task[:verification]
      when :exact_count
        return 1.0 if result[:ground_truth_match]
        return 0.5 if result[:response].present?
        0.0

      when :contains_all
        return 1.0 if result[:ground_truth_match]
        0.3

      when :canvas_loaded
        expected = task[:expected_canvas]
        return 1.0 if result[:canvas_loaded] == expected
        return 0.5 if result[:canvas_loaded].present?
        0.0

      when :object_created_and_verified
        return 1.0 if result[:verification_details]&.dig(:created) && result[:verification_details]&.dig(:verified)
        return 0.5 if result[:verification_details]&.dig(:created)
        0.0

      when :asset_created
        return 1.0 if result[:verification_details]&.dig(:asset_id).present?
        0.0

      when :plan_created
        return 1.0 if result[:verification_details]&.dig(:plan_id).present?
        0.5 if result[:tools_used]&.include?('delegate_to_planner')
        0.0

      when :clarification_requested
        response = result[:response].to_s.downcase
        clarification_indicators = ['what kind', 'what type', 'could you', 'which', 'clarify', 'more details']
        return 1.0 if clarification_indicators.any? { |i| response.include?(i) }
        0.0

      when :no_hallucination
        forbidden = task[:forbidden_patterns] || []
        response = result[:response].to_s
        hallucinated = forbidden.any? { |pattern| response.match?(pattern) }
        return 1.0 unless hallucinated
        0.0

      else
        # Default: response present and no errors
        result[:response].present? ? 0.7 : 0.0
      end
    end

    def score_completeness(task, result)
      return 0.0 if result[:errors]&.any?

      # Check if all expected tools were used
      expected_tools = task[:expected_tools] || []
      used_tools = result[:tools_used] || []

      if expected_tools.any?
        matched = (expected_tools & used_tools).count
        tool_score = matched.to_f / expected_tools.count
      else
        tool_score = 1.0
      end

      # Check if expected fields/content are present
      content_score = 1.0
      if task[:expected_fields]
        response = result[:response].to_s.downcase
        matched_fields = task[:expected_fields].count { |f| response.include?(f.downcase) }
        content_score = matched_fields.to_f / task[:expected_fields].count
      end

      (tool_score * 0.5 + content_score * 0.5).round(2)
    end

    def score_efficiency(task, result, latency_ms)
      scores = []

      # Latency score
      max_latency = task[:max_latency_ms] || 30_000
      if latency_ms <= max_latency
        latency_score = 1.0 - (latency_ms.to_f / max_latency * 0.5)  # Up to 0.5 penalty for being slow
      else
        latency_score = 0.5 * (max_latency.to_f / latency_ms)  # Penalty for exceeding
      end
      scores << latency_score.clamp(0.0, 1.0)

      # Tool call efficiency
      if task[:max_tool_calls]
        actual = result[:tool_calls] || 0
        if actual <= task[:max_tool_calls]
          scores << 1.0
        else
          scores << (task[:max_tool_calls].to_f / actual).clamp(0.0, 1.0)
        end
      end

      scores.sum / scores.count
    end

    def score_groundedness(task, result)
      # Check for hallucination first
      if task[:forbidden_patterns]
        response = result[:response].to_s
        hallucinated = task[:forbidden_patterns].any? { |p| response.match?(p) }
        return 0.0 if hallucinated
      end

      # For canvas-loading tasks, groundedness is about using the tool correctly
      if task[:verification] == :canvas_loaded
        tools_used = result[:tools_used] || []
        return 1.0 if tools_used.include?('load_canvas')
        return 0.3
      end

      # Did it use data tools when it should have?
      if task[:expected_tools]&.any?
        tools_used = result[:tools_used] || []
        data_tools = %w[get_data get_schema query explain_query]
        expected_data_tools = task[:expected_tools] & data_tools
        
        # Only check for data tools if they're actually expected
        if expected_data_tools.any?
          used_data_tool = (tools_used & data_tools).any?
          return 1.0 if used_data_tool
          return 0.3  # Didn't use data tools when expected
        end
      end

      # Default: if no specific grounding needed
      1.0
    end

    def score_robustness(task, result)
      return 1.0 unless task[:expected_behavior]

      case task[:expected_behavior]
      when :asks_clarification
        response = result[:response].to_s.downcase
        asks = response.include?('?') || response.include?('clarify') || response.include?('what')
        return 1.0 if asks
        0.0

      when :refuses_gracefully
        response = result[:response].to_s.downcase
        refused = response.include?("can't") || response.include?('cannot') || response.include?('unable')
        helpful = response.include?('instead') || response.include?('however') || response.include?('can help')
        return 1.0 if refused && helpful
        return 0.5 if refused
        0.0

      when :identifies_conflict
        response = result[:response].to_s.downcase
        identified = response.include?('conflict') || response.include?('contradiction') || 
                    (response.include?('create') && response.include?("don't"))
        return 1.0 if identified
        0.5

      else
        1.0
      end
    end

    def score_recovery(task, result)
      return 1.0 unless task[:category] == :plan_recovery

      if result[:verification_details]&.dig(:recovery_attempted)
        return 1.0
      end

      response = result[:response].to_s.downcase
      recovery_terms = ['retry', 'skip', 'alternative', 'recover', 'try again', 'reassign']
      mentioned_recovery = recovery_terms.any? { |t| response.include?(t) }

      mentioned_recovery ? 0.8 : 0.2
    end

    # ============================================
    # TASK EXECUTION (INTERNAL)
    # ============================================

    def execute_task(task)
      session_id = "bob3_#{SecureRandom.hex(4)}"
      
      scout = V3::AgentLoop # V3 migration stub.new(@user, @entity, session_id)

      response_text = ""
      tools_used = []
      tool_calls = 0
      canvas_loaded = nil
      errors = []
      delegation_occurred = false

      callback = ->(chunk) {
        if chunk.is_a?(String)
          response_text += chunk
        elsif chunk.is_a?(Hash)
          type = (chunk[:type] || chunk['type']).to_s

          if type == 'tool_start' || type == 'tool_complete'
            tool_name = chunk[:name] || chunk[:tool_name] || chunk['name'] || chunk['tool_name']
            tools_used << tool_name if tool_name.present?
            tool_calls += 1
          end

          if type == 'canvas_loaded' || type == 'canvas_update'
            canvas_loaded = chunk[:canvas_type] || chunk['canvas_type'] ||
                           chunk[:canvas] || chunk['canvas']
          end
          
          if type == 'auto_canvas'
            canvas_loaded = chunk[:canvas] || chunk['canvas']
          end

          if type == 'agent_delegated'
            delegation_occurred = true
          end

          if type == 'content_chunk'
            content = chunk[:content] || chunk['content']
            response_text += content if content.present?
          end
        end
      }

      # Handle multi-turn conversations
      if task[:conversation]
        task[:conversation].each do |turn|
          if turn[:role] == 'user'
            scout.process_message_with_tools_streaming(turn[:content], callback, [], nil)
          end
        end
      else
        scout.process_message_with_tools_streaming(task[:request], callback, [], nil)
      end

      # Verify against ground truth if provided
      ground_truth_match = false
      if task[:ground_truth].is_a?(Proc)
        expected = task[:ground_truth].call(self)
        ground_truth_match = verify_ground_truth(task[:verification], expected, response_text)
      end

      # Run verification
      verification_details = run_verification(task, response_text, tools_used, canvas_loaded)

      {
        response: response_text,
        tool_calls: tool_calls,
        tools_used: tools_used.uniq,
        agents_used: delegation_occurred ? ['delegated'] : [],
        canvas_loaded: canvas_loaded,
        ground_truth_match: ground_truth_match,
        verification_details: verification_details,
        errors: errors
      }
    rescue => e
      {
        response: nil,
        tool_calls: 0,
        tools_used: [],
        agents_used: [],
        errors: [e.message]
      }
    end

    def verify_ground_truth(verification_type, expected, response)
      case verification_type
      when :exact_count
        response.to_s.include?(expected.to_s)

      when :contains_all
        return false unless expected.is_a?(Array)
        expected.all? { |item| response.to_s.downcase.include?(item.to_s.downcase) }

      when :approximate_value
        # Extract number from response and compare
        numbers = response.to_s.scan(/[\d,]+\.?\d*/).map { |n| n.gsub(',', '').to_f }
        tolerance = 0.1
        numbers.any? { |n| (n - expected.to_f).abs / expected.to_f <= tolerance }

      when :breakdown_correct
        return false unless expected.is_a?(Hash)
        expected.all? { |k, v| response.to_s.include?(v.to_s) }

      else
        false
      end
    end

    def run_verification(task, response, tools_used, canvas_loaded)
      details = {}

      case task[:verification]
      when :object_created_and_verified
        # Check if object was actually created
        if task[:expected_tools]&.include?('create_object')
          created = tools_used.include?('create_object')
          verified = tools_used.include?('get_data')
          details[:created] = created
          details[:verified] = verified
        end

      when :asset_created
        asset_type = task[:asset_type]
        if asset_type
          recent = asset_type.where(entity: @entity).where('created_at > ?', 1.minute.ago).first
          details[:asset_id] = recent&.id
          details[:asset_type] = asset_type.name
        end

      when :plan_created
        recent_plan = ExecutionPlan.where(entity: @entity).where('created_at > ?', 1.minute.ago).first
        details[:plan_id] = recent_plan&.id
        details[:plan_title] = recent_plan&.title
        details[:plan_complexity] = recent_plan&.complexity

      when :module_created
        recent_module = AppModule.where(entity: @entity).where('created_at > ?', 2.minutes.ago).first
        details[:module_id] = recent_module&.id
        details[:module_name] = recent_module&.name

      when :canvas_loaded
        details[:expected] = task[:expected_canvas]
        details[:actual] = canvas_loaded
        details[:match] = canvas_loaded == task[:expected_canvas]
      end

      details
    end

    # ============================================
    # SETUP HELPERS
    # ============================================

    def ensure_contacts(count, lifecycle_stages: nil, with_tags: false)
      existing = Contact.where(entity: @entity).count
      needed = count - existing

      # Valid values:
      # - status: active, inactive, unsubscribed, bounced
      # - lifecycle_stage: subscriber, lead, mql, sql, opportunity, customer, evangelist
      lifecycle_stages ||= ['lead']

      needed.times do |i|
        Contact.create!(
          entity: @entity,
          user: @user,  # Required!
          first_name: "Benchmark",
          last_name: "Contact#{i}",
          email: "benchmark#{i}@test.com",
          status: 'active',  # Valid status
          lifecycle_stage: lifecycle_stages.sample
        )
      end
    end

    def ensure_contacts_with_lifecycle_stage(count)
      # Ensure some leads exist for the multi-step operation test
      existing = Contact.where(entity: @entity).count
      needed = count - existing

      needed.times do |i|
        # Half as leads, half as other lifecycle stages
        lifecycle = i < (needed / 2) ? 'lead' : %w[mql customer].sample
        Contact.create!(
          entity: @entity,
          user: @user,  # Required!
          first_name: "Benchmark",
          last_name: "Contact#{existing + i}",
          email: "benchmark#{existing + i}@test.com",
          status: 'active',  # Valid status
          lifecycle_stage: lifecycle
        )
      end
    end

    def ensure_campaigns(count)
      existing = Campaign.where(entity: @entity).count
      needed = count - existing

      needed.times do |i|
        Campaign.create!(
          entity: @entity,
          user: @user,
          name: "Benchmark Campaign #{i}",
          status: 'draft'
        )
      end
    end

    def ensure_opportunities(count, with_values: false)
      existing = Opportunity.where(entity: @entity).count
      needed = count - existing

      needed.times do |i|
        Opportunity.create!(
          entity: @entity,
          user: @user,
          name: "Benchmark Deal #{i}",
          stage: %w[lead qualified proposal].sample,
          value: with_values ? rand(1000..50000) : nil
        )
      end
    end

    def create_test_plan(title: 'Test Plan', steps: 2)
      phases = [{
        id: 'phase_1',
        name: 'Test Phase',
        status: 'pending',
        steps: steps.times.map do |i|
          {
            id: "step_#{i}",
            name: "Test Step #{i}",
            description: "Benchmark test step",
            status: 'pending',
            agent: nil,
            tools_needed: [],
            dependencies: i > 0 ? ["step_#{i - 1}"] : []
          }
        end
      }]

      ExecutionPlan.create!(
        entity: @entity,
        user: @user,
        title: title,
        original_request: 'Benchmark test plan',
        complexity: 'simple',
        status: 'ready',
        phases: phases,
        total_steps: steps
      )
    end

    def create_failing_plan_step
      plan = create_test_plan(steps: 1)
      plan.update!(status: 'executing')
      plan.mark_step_started!('step_0')
      plan.mark_step_failed!('step_0', error: 'Simulated failure for benchmark', auto_recover: false)
      plan
    end

    def add_plan_dependency(dependent, blocker)
      orchestrator = Planner::OrchestratorService.new(entity: @entity)
      orchestrator.add_dependency(dependent_plan: dependent, depends_on_plan: blocker)
    end

    # ============================================
    # REPORTING
    # ============================================

    def generate_report
      puts "=" * 80
      puts "📊 BOB v3.0 BENCHMARK RESULTS"
      puts "=" * 80
      puts ""

      # Overall
      total = @results.count
      passed = @results.count { |r| r[:passed] }
      avg_score = (@results.sum { |r| r[:total_score] } / total).round(3)

      puts "OVERALL: #{passed}/#{total} passed (#{(passed.to_f / total * 100).round(1)}%)"
      puts "Average Score: #{(avg_score * 100).round(1)}%"
      puts ""

      # By Tier
      puts "BY TIER:"
      puts "-" * 40
      BusinessBenchmarkV3::DIFFICULTY_TIERS.each do |tier_key, tier_info|
        tier_results = @results.select { |r| r[:tier] == tier_key }
        next if tier_results.empty?

        tier_passed = tier_results.count { |r| r[:passed] }
        tier_avg = (tier_results.sum { |r| r[:total_score] } / tier_results.count).round(3)
        expected = (TIER_EXPECTATIONS[tier_key] * 100).round

        status = tier_passed >= (tier_results.count * TIER_EXPECTATIONS[tier_key] * 0.8) ? "✓" : "✗"
        puts "  #{status} #{tier_info[:name]}: #{tier_passed}/#{tier_results.count} (#{(tier_avg * 100).round(1)}%) [Expected: #{expected}%]"
      end
      puts ""

      # By Dimension
      puts "BY DIMENSION:"
      puts "-" * 40
      BusinessBenchmarkV3::SCORING_DIMENSIONS.each do |dim, config|
        dim_scores = @results.map { |r| r[:dimension_scores][dim] || 0.0 }
        avg = (dim_scores.sum / dim_scores.count).round(3)
        puts "  #{dim.to_s.titleize}: #{(avg * 100).round(1)}%"
      end
      puts ""

      # By Category
      puts "BY CATEGORY:"
      puts "-" * 40
      @results.group_by { |r| r[:category] }.each do |cat, cat_results|
        cat_passed = cat_results.count { |r| r[:passed] }
        cat_avg = (cat_results.sum { |r| r[:total_score] } / cat_results.count).round(3)
        puts "  #{BusinessBenchmarkV3::CATEGORIES[cat] || cat}: #{cat_passed}/#{cat_results.count} (#{(cat_avg * 100).round(1)}%)"
      end
      puts ""

      # Latency Stats
      latencies = @results.map { |r| r[:latency_ms] }.compact
      if latencies.any?
        puts "LATENCY:"
        puts "-" * 40
        puts "  Min: #{latencies.min}ms"
        puts "  Max: #{latencies.max}ms"
        puts "  Avg: #{(latencies.sum / latencies.count).round}ms"
        puts "  p95: #{latencies.sort[(latencies.count * 0.95).floor]}ms"
        puts ""
      end

      # Tool Usage
      all_tools = @results.flat_map { |r| r[:tools_used] || [] }.compact
      tool_freq = all_tools.tally.sort_by { |_, v| -v }
      if tool_freq.any?
        puts "TOP TOOLS USED:"
        puts "-" * 40
        tool_freq.first(10).each { |tool, count| puts "  #{tool}: #{count}" }
        puts ""
      end

      # Failures
      failures = @results.reject { |r| r[:passed] }
      if failures.any?
        puts "❌ FAILURES (#{failures.count}):"
        puts "-" * 40
        failures.first(10).each do |f|
          puts "  • #{f[:name]} (#{f[:tier]}) - Score: #{(f[:total_score] * 100).round}%"
          puts "    Errors: #{f[:errors].join(', ')}" if f[:errors]&.any?
        end
        puts ""
      end

      puts "=" * 80

      {
        total: total,
        passed: passed,
        avg_score: avg_score,
        results: @results
      }
    end

    def run_tasks(tasks, progress_callback: nil)
      tasks.each_with_index do |task, idx|
        progress_callback&.call(idx + 1, tasks.size, task[:name])
        result = run_task(task)
        @results << result
        sleep(0.3)
      end
      @results
    end
  end
end


