# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Business Benchmark Runner v4.0
  # Enhanced Evaluation Harness with Factory Testing
  # ============================================
  class BusinessBenchmarkRunnerV4
    attr_reader :entity, :user, :results, :run_id, :last_response

    # Stricter tier expectations
    TIER_EXPECTATIONS = {
      tier_1: 0.98,  # Basic: expect 98%
      tier_2: 0.90,  # Standard: expect 90%
      tier_3: 0.70,  # Advanced: expect 70%
      tier_4: 0.40,  # Expert: expect 40%
      tier_5: 0.15   # Nightmare: expect 15%
    }.freeze

    def initialize(entity: nil, user: nil, use_test_env: true, verbose: nil)
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
      @last_response = nil
      
      # Verbose mode: nil = auto (verbose for single task), true/false = explicit
      @verbose = verbose
      
      # Check if queue is running for async tasks
      check_queue_status
    end
    
    def check_queue_status
      # Check if Solid Queue is processing jobs
      if defined?(SolidQueue::Process)
        running_processes = SolidQueue::Process.where('last_heartbeat_at > ?', 30.seconds.ago).count
        if running_processes > 0
          log "✓ Solid Queue running (#{running_processes} workers)", level: :success
        else
          log "⚠️  No Solid Queue workers detected! Async tasks won't complete.", level: :warning
          log "   Run: bundle exec rake solid_queue:start", level: :warning
        end
      end
    rescue => e
      # Queue check failed, continue anyway
      Rails.logger.debug "[BOB v4] Queue check skipped: #{e.message}"
    end

    def verbose?
      return @verbose unless @verbose.nil?
      # Auto-detect: verbose for single task runs
      @single_task_mode == true
    end

    def log(message, level: :info)
      return unless verbose?
      
      prefix = case level
               when :debug then "    🔍"
               when :info then "    ℹ️ "
               when :success then "    ✅"
               when :warning then "    ⚠️ "
               when :error then "    ❌"
               when :tool then "    🔧"
               when :progress then "    ⏳"
               else "    "
               end
      puts "#{prefix} #{message}"
    end

    # ============================================
    # MAIN EXECUTION METHODS
    # ============================================

    def run_tier(tier, progress_callback: nil)
      tasks = BusinessBenchmarkV4.tasks_by_tier(tier)
      run_tasks(tasks, progress_callback: progress_callback)
    end

    def run_category(category, progress_callback: nil)
      tasks = BusinessBenchmarkV4.tasks_by_category(category)
      run_tasks(tasks, progress_callback: progress_callback)
    end

    def run_factories(progress_callback: nil)
      tasks = BusinessBenchmarkV4.factory_tasks
      puts "\n🏭 Running Factory Integration Tests (#{tasks.count} tasks)"
      run_tasks(tasks, progress_callback: progress_callback)
    end

    def run_single(task_id)
      task = BusinessBenchmarkV4.task(task_id)
      return nil unless task

      @single_task_mode = true
      @verbose = true  # Always verbose for single task
      run_task(task)
    end

    def run_full_benchmark(progress_callback: nil)
      puts "\n" + "=" * 80
      puts "🏢 BUSINESS OPERATIONS BENCHMARK (BOB) v4.0 - NIGHTMARE MODE"
      puts "=" * 80
      puts "Total tasks: #{BusinessBenchmarkV4.total_tasks}"
      puts "Verification coverage: #{BusinessBenchmarkV4.verification_coverage}"
      puts "=" * 80
      puts ""

      BusinessBenchmarkV4::DIFFICULTY_TIERS.each do |tier_key, tier_info|
        tasks = BusinessBenchmarkV4.tasks_by_tier(tier_key)
        next if tasks.empty?

        puts "📊 #{tier_info[:name]} (Tier #{tier_key.to_s.split('_').last})"
        puts "   Expected: #{(tier_info[:expected] * 100).round}%+ success"
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
      puts "\n⚡ QUICK BOB v4.0 BENCHMARK"
      puts "=" * 50

      BusinessBenchmarkV4::DIFFICULTY_TIERS.each do |tier_key, tier_info|
        tasks = BusinessBenchmarkV4.tasks_by_tier(tier_key).sample(tasks_per_tier)
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

      puts "\n" + "─" * 60 if verbose?
      log "TASK: #{task[:name]} [#{task[:id]}]", level: :info
      log "Tier: #{task[:tier]} | Category: #{task[:category]} | Verification: #{task[:verification]}", level: :debug

      # Run setup if provided
      if task[:setup].is_a?(Proc)
        begin
          log "Running setup...", level: :progress
          task[:setup].call(self)
          log "Setup complete", level: :success
        rescue => e
          log "Setup failed: #{e.message}", level: :warning
          Rails.logger.warn "[BOB v4] Setup failed for #{task[:id]}: #{e.message}"
        end
      end

      begin
        # Execute the task
        log "Executing task...", level: :progress
        execution_result = execute_task(task)
        @last_response = execution_result[:response]

        latency_ms = ((Time.current - start_time) * 1000).round
        log "Execution took #{latency_ms}ms", level: :info

        # Wait for async operations if needed
        if task[:async_timeout] && task[:verification].in?([:artifact_created, :workflow_complete])
          log "Waiting for async operations (up to #{task[:async_timeout]}s)...", level: :progress
          execution_result = wait_for_async(task, execution_result, task[:async_timeout])
        end

        # Run verification with the improved harness
        log "Running verification (#{task[:verification]})...", level: :progress
        verification_result = run_enhanced_verification(task, execution_result)
        
        if verification_result[:passed]
          log "Verification PASSED", level: :success
        else
          log "Verification FAILED", level: :error
          if verification_result[:ground_truth]
            log "  Expected: #{verification_result[:ground_truth].to_s.truncate(80)}", level: :debug
          end
          if verification_result[:actual]
            log "  Actual: #{verification_result[:actual].to_s.truncate(80)}", level: :debug
          end
          if verification_result[:details].present?
            log "  Details: #{verification_result[:details].inspect.truncate(100)}", level: :debug
          end
        end

        # Score each dimension
        dimension_scores = score_dimensions(task, execution_result, verification_result, latency_ms)
        
        if verbose?
          log "Dimension scores:", level: :info
          dimension_scores.each do |dim, score|
            log "  #{dim}: #{(score * 100).round(1)}%", level: :debug
          end
        end

        # Calculate weighted total
        total_score = calculate_total_score(dimension_scores)

        # Determine pass/fail - more meaningful criteria
        # 1. Verification must pass (core requirement)
        # 2. Must meet minimum absolute threshold (50% for all tiers)
        # 3. Higher tiers get some leniency on total score
        verification_passed = verification_result[:passed]
        min_absolute_threshold = 0.50  # Always require at least 50%
        tier_threshold = [TIER_EXPECTATIONS[task[:tier]] * 0.7, min_absolute_threshold].max
        
        # Pass requires BOTH verification success AND score threshold
        passed = verification_passed && total_score >= tier_threshold

        # Show clear pass/fail reason
        if passed
          log "RESULT: ✓ PASSED (#{(total_score * 100).round(1)}%)", level: :success
        else
          if !verification_passed
            log "RESULT: ✗ FAILED - Verification failed (score: #{(total_score * 100).round(1)}%)", level: :error
          else
            log "RESULT: ✗ FAILED - Score #{(total_score * 100).round(1)}% below threshold #{(tier_threshold * 100).round(1)}%", level: :error
          end
        end

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
          response: execution_result[:response],
          verification: verification_result,
          errors: execution_result[:errors]
        }

        # Cleanup if provided
        if task[:cleanup].is_a?(Proc)
          begin
            log "Running cleanup...", level: :debug
            task[:cleanup].call(self)
          rescue => e
            log "Cleanup failed: #{e.message}", level: :warning
            Rails.logger.warn "[BOB v4] Cleanup failed for #{task[:id]}: #{e.message}"
          end
        end

        result
      rescue => e
        log "TASK EXCEPTION: #{e.message}", level: :error
        Rails.logger.error "[BOB v4] Task #{task[:id]} failed: #{e.message}"
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
    # ENHANCED VERIFICATION HARNESS
    # ============================================

    def run_enhanced_verification(task, execution_result)
      verification = {
        type: task[:verification],
        level: BusinessBenchmarkV4::VERIFICATION_TYPES.dig(task[:verification], :level) || 1,
        passed: false,
        details: {},
        ground_truth: nil,
        actual: nil,
        match: false
      }

      case task[:verification]
      when :exact_match
        # L4: Exact output matching
        if task[:ground_truth].is_a?(Proc)
          verification[:ground_truth] = task[:ground_truth].call(self)
        end
        
        if task[:extract_answer].is_a?(Proc)
          verification[:actual] = task[:extract_answer].call(execution_result[:response])
        else
          verification[:actual] = execution_result[:response]
        end
        
        verification[:match] = verification[:actual].to_s.strip == verification[:ground_truth].to_s.strip
        verification[:passed] = verification[:match]
        verification[:details][:similarity] = string_similarity(verification[:actual].to_s, verification[:ground_truth].to_s)

      when :canvas_loaded
        # L3: Canvas side effect
        verification[:ground_truth] = task[:expected_canvas]
        verification[:actual] = execution_result[:canvas_loaded]
        verification[:match] = verification[:actual] == verification[:ground_truth]
        verification[:passed] = verification[:match]

      when :artifact_created
        # L3: Database artifact verification
        artifact = nil
        if task[:artifact_query].is_a?(Proc)
          artifact = task[:artifact_query].call(@entity)
        elsif task[:artifact_type]
          artifact = task[:artifact_type].where(entity: @entity)
                                         .where('created_at > ?', 5.minutes.ago)
                                         .first
        end
        
        verification[:actual] = artifact
        verification[:passed] = artifact.present?
        verification[:details][:artifact_id] = artifact&.id
        verification[:details][:artifact_type] = task[:artifact_type]&.name
        
        # Check expected fields if specified
        if artifact && task[:expected_fields]
          field_results = {}
          task[:expected_fields].each do |field, expected|
            actual_value = artifact.send(field) rescue nil
            matches = actual_value.to_s.downcase.include?(expected.to_s.downcase)
            field_results[field] = { expected: expected, actual: actual_value, matches: matches }
          end
          
          field_matches = field_results.values.all? { |r| r[:matches] }
          verification[:details][:field_matches] = field_matches
          verification[:details][:field_results] = field_results unless field_matches
          verification[:passed] &&= field_matches
        end

      when :workflow_complete
        # L5: Full workflow verification
        if task[:workflow_steps].is_a?(Array)
          step_results = task[:workflow_steps].map do |step|
            passed = step[:check].is_a?(Proc) ? step[:check].call(self) : false
            { description: step[:description], passed: passed }
          end
          
          verification[:details][:steps] = step_results
          verification[:passed] = step_results.all? { |s| s[:passed] }
          verification[:details][:steps_passed] = step_results.count { |s| s[:passed] }
          verification[:details][:steps_total] = step_results.count
        end

      when :tool_args_match
        # L2: Tool argument verification
        expected_tools = task[:expected_tools] || []
        verification[:passed] = expected_tools.all? { |t| execution_result[:tools_used].include?(t) }
        verification[:details][:expected_tools] = expected_tools
        verification[:details][:actual_tools] = execution_result[:tools_used]
        
        # Check behavior if specified
        if task[:behavior_check].is_a?(Proc)
          behavior_passed = task[:behavior_check].call(execution_result[:response])
          verification[:details][:behavior_passed] = behavior_passed
          verification[:passed] &&= behavior_passed
        end

      when :tool_called
        # L1: Basic tool invocation check
        expected_tools = task[:expected_tools] || []
        verification[:passed] = expected_tools.any? { |t| execution_result[:tools_used].include?(t) }
      end

      verification
    end

    def wait_for_async(task, execution_result, timeout_seconds)
      log "Async wait started (timeout: #{timeout_seconds}s)", level: :progress
      Rails.logger.info "[BOB v4] Waiting up to #{timeout_seconds}s for async operations..."
      
      start_time = Time.current
      poll_interval = 5  # Check every 5 seconds
      poll_count = 0
      
      while (Time.current - start_time) < timeout_seconds
        poll_count += 1
        elapsed = (Time.current - start_time).round
        
        # Re-run verification to check if async operation completed
        if task[:artifact_query].is_a?(Proc)
          artifact = task[:artifact_query].call(@entity)
          if artifact.present?
            log "Async artifact found after #{elapsed}s (poll ##{poll_count})", level: :success
            Rails.logger.info "[BOB v4] Async artifact found after #{elapsed}s"
            return execution_result
          end
        end
        
        if task[:workflow_steps].is_a?(Array)
          step_results = task[:workflow_steps].map.with_index do |step, idx|
            begin
              passed = step[:check].is_a?(Proc) ? step[:check].call(self) : false
              { index: idx, description: step[:description], passed: passed }
            rescue => e
              { index: idx, description: step[:description], passed: false, error: e.message }
            end
          end
          
          steps_passed = step_results.count { |s| s[:passed] }
          
          # Log step-by-step details every 5 polls for debugging
          if poll_count == 1 || poll_count % 5 == 0
            log "Poll ##{poll_count} (#{elapsed}s): #{steps_passed}/#{task[:workflow_steps].count} steps complete", level: :progress
            step_results.each do |s|
              status = s[:passed] ? "✓" : "✗"
              error_info = s[:error] ? " (#{s[:error].truncate(40)})" : ""
              log "    Step #{s[:index]+1}: #{status} #{s[:description]}#{error_info}", level: :debug
            end
          else
            log "Poll ##{poll_count} (#{elapsed}s): #{steps_passed}/#{task[:workflow_steps].count} steps complete", level: :progress
          end
          
          if steps_passed == task[:workflow_steps].count
            log "Async workflow completed after #{elapsed}s", level: :success
            Rails.logger.info "[BOB v4] Async workflow completed after #{elapsed}s"
            return execution_result
          end
        end
        
        sleep(poll_interval)
      end
      
      log "Async TIMEOUT after #{timeout_seconds}s", level: :warning
      Rails.logger.warn "[BOB v4] Async timeout after #{timeout_seconds}s"
      execution_result
    end

    def string_similarity(s1, s2)
      return 1.0 if s1 == s2
      return 0.0 if s1.nil? || s2.nil?
      
      s1_down = s1.to_s.downcase.strip
      s2_down = s2.to_s.downcase.strip
      
      return 1.0 if s1_down == s2_down
      
      # Simple word overlap similarity
      words1 = s1_down.split(/\W+/)
      words2 = s2_down.split(/\W+/)
      
      return 0.0 if words1.empty? || words2.empty?
      
      overlap = (words1 & words2).count
      (2.0 * overlap) / (words1.count + words2.count)
    end

    # ============================================
    # SCORING
    # ============================================

    def score_dimensions(task, execution_result, verification, latency_ms)
      scores = {}

      # Correctness (0.0 to 1.0) - based on verification
      scores[:correctness] = score_correctness(task, verification)

      # Completeness (0.0 to 1.0)
      scores[:completeness] = score_completeness(task, execution_result)

      # Efficiency (0.0 to 1.0)
      scores[:efficiency] = score_efficiency(task, execution_result, latency_ms)

      # Groundedness (0.0 to 1.0)
      scores[:groundedness] = score_groundedness(task, execution_result)

      # Integration (0.0 to 1.0) - new dimension for v4
      scores[:integration] = score_integration(task, verification)

      # Recovery (0.0 to 1.0)
      scores[:recovery] = score_recovery(task, execution_result)

      scores
    end

    def calculate_total_score(dimension_scores)
      total = 0.0

      BusinessBenchmarkV4::SCORING_DIMENSIONS.each do |dim, config|
        score = dimension_scores[dim] || 0.0
        weight = config[:weight]
        total += score * weight
      end

      total.round(4)
    end

    def score_correctness(task, verification)
      return 0.0 unless verification
      return 1.0 if verification[:passed]
      
      # Partial credit based on verification level
      case task[:verification]
      when :exact_match
        verification.dig(:details, :similarity) || 0.0
      when :workflow_complete
        steps_passed = verification.dig(:details, :steps_passed) || 0
        steps_total = verification.dig(:details, :steps_total) || 1
        steps_passed.to_f / steps_total
      when :artifact_created
        verification[:actual].present? ? 0.5 : 0.0
      else
        0.0
      end
    end

    def score_completeness(task, result)
      return 0.0 if result[:errors]&.any?

      scores = []
      
      # Check expected tools usage
      expected_tools = task[:expected_tools] || []
      used_tools = result[:tools_used] || []

      if expected_tools.any?
        matched = (expected_tools & used_tools).count
        scores << (matched.to_f / expected_tools.count)
      end
      
      # For workflow tasks, check if we made progress
      if task[:verification] == :workflow_complete && task[:workflow_steps].present?
        steps_passed = task[:workflow_steps].count do |step|
          step[:check].is_a?(Proc) ? step[:check].call(self) : false
        rescue => e
          false
        end
        scores << (steps_passed.to_f / task[:workflow_steps].count)
      end
      
      # For artifact tasks, check if artifact was created
      if task[:verification] == :artifact_created && task[:artifact_query].is_a?(Proc)
        artifact = task[:artifact_query].call(@entity) rescue nil
        scores << (artifact.present? ? 1.0 : 0.0)
      end
      
      # If we have no checks, just verify there's a response
      if scores.empty?
        return result[:response].present? ? 1.0 : 0.0
      end
      
      # Average all completeness checks
      scores.sum / scores.count
    end

    def score_efficiency(task, result, latency_ms)
      scores = []

      # Latency score
      max_latency = task[:max_latency_ms] || 30_000
      if latency_ms <= max_latency
        latency_score = 1.0 - (latency_ms.to_f / max_latency * 0.3)
      else
        latency_score = 0.7 * (max_latency.to_f / latency_ms)
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
      # For canvas tasks, check if canvas loaded (via tool OR auto-canvas)
      if task[:verification] == :canvas_loaded
        # Canvas can load via load_canvas tool OR auto-canvas system
        canvas_loaded = result[:canvas_loaded].present? || 
                       result[:tools_used]&.include?('load_canvas')
        return canvas_loaded ? 1.0 : 0.3
      end

      # For data tasks, check if data tools were used
      data_tools = %w[get_data get_schema create_object update_object query_document_content]
      if task[:expected_tools]&.any? { |t| data_tools.include?(t) }
        return (result[:tools_used] & data_tools).any? ? 1.0 : 0.3
      end
      
      # For complex tasks (tier 3+), check if appropriate tools were used
      if task[:tier].in?([:tier_3, :tier_4, :tier_5])
        delegation_tools = %w[delegate_to_agent delegate_to_planner start_module_design start_app_design]
        if (result[:tools_used] & delegation_tools).any?
          return 1.0
        end
      end

      # Default: response present and no obvious hallucination
      result[:response].present? ? 1.0 : 0.0
    end

    def score_integration(task, verification)
      return 1.0 unless task[:verification].in?([:artifact_created, :workflow_complete])
      
      return 1.0 if verification[:passed]
      
      # Partial credit for workflow steps
      if verification.dig(:details, :steps_total)
        passed = verification.dig(:details, :steps_passed) || 0
        total = verification[:details][:steps_total]
        return passed.to_f / total
      end
      
      0.0
    end

    def score_recovery(task, result)
      return 1.0 unless task[:category] == :failure_recovery

      if result[:errors]&.none?
        return 1.0
      end

      response = result[:response].to_s.downcase
      recovery_terms = ['retry', 'skip', 'alternative', 'recover', 'try again', 'fix']
      recovery_terms.any? { |t| response.include?(t) } ? 0.8 : 0.2
    end

    # ============================================
    # TASK EXECUTION (INTERNAL)
    # ============================================

    def execute_task(task)
      session_id = "bob4_#{SecureRandom.hex(4)}"
      
      log "Creating Scout session: #{session_id}", level: :debug
      scout = V3::AgentLoop # V3 migration stub.new(@user, @entity, session_id)

      response_text = ""
      tools_used = []
      tool_calls = 0
      canvas_loaded = nil
      errors = []
      chunk_count = 0

      last_progress_time = Time.current
      
      callback = ->(chunk) {
        chunk_count += 1
        
        if chunk.is_a?(String)
          response_text += chunk
          # Show streaming progress every 5 seconds
          if Time.current - last_progress_time > 5
            log "Streaming... #{response_text.length} chars, #{tool_calls} tools", level: :progress
            last_progress_time = Time.current
          end
        elsif chunk.is_a?(Hash)
          type = (chunk[:type] || chunk['type']).to_s

          if type == 'tool_start'
            tool_name = chunk[:name] || chunk[:tool_name] || chunk['name'] || chunk['tool_name']
            tools_used << tool_name if tool_name.present?
            tool_calls += 1
            log "Tool START: #{tool_name}", level: :tool
            if verbose? && chunk[:arguments].present?
              args_preview = chunk[:arguments].to_s.truncate(100)
              log "  Args: #{args_preview}", level: :debug
            end
          end
          
          if type == 'tool_complete'
            tool_name = chunk[:name] || chunk[:tool_name] || chunk['name'] || chunk['tool_name']
            success = chunk[:success] || chunk['success']
            status = success ? "✓" : "✗"
            log "Tool COMPLETE: #{tool_name} #{status}", level: :tool
          end

          if type == 'canvas_loaded' || type == 'canvas_update'
            canvas_loaded = chunk[:canvas_type] || chunk['canvas_type'] ||
                           chunk[:canvas] || chunk['canvas']
            log "Canvas loaded: #{canvas_loaded}", level: :success
          end
          
          if type == 'auto_canvas'
            canvas_loaded = chunk[:canvas] || chunk['canvas']
            log "Auto-canvas: #{canvas_loaded}", level: :info
          end

          if type == 'content_chunk'
            content = chunk[:content] || chunk['content']
            response_text += content if content.present?
          end
          
          if type == 'error'
            err_msg = chunk[:message] || chunk['message']
            errors << err_msg
            log "ERROR: #{err_msg}", level: :error
          end
          
          if type == 'thinking' || type == 'reasoning'
            log "AI thinking...", level: :progress
          end
        end
      }

      # Handle multi-turn conversations
      # IMPORTANT: Save messages like the real controller does - this enables memory to work
      conversation_history = []
      
      if task[:conversation]
        log "Multi-turn conversation (#{task[:conversation].count} turns)", level: :info
        task[:conversation].each_with_index do |turn, idx|
          if turn[:role] == 'user'
            log "Turn #{idx + 1}: \"#{turn[:content].truncate(60)}\"", level: :info
            
            # Save user message to DB (like controller does)
            save_benchmark_message('user', turn[:content], session_id)
            conversation_history << { role: 'user', content: turn[:content] }
            
            # Process with conversation history
            turn_response = ""
            turn_callback = ->(chunk) {
              callback.call(chunk)  # Forward to main callback
              if chunk.is_a?(String)
                turn_response += chunk
              elsif chunk.is_a?(Hash) && chunk[:type] == 'content_chunk'
                turn_response += (chunk[:content] || '')
              end
            }
            
            scout.process_message_with_tools_streaming(turn[:content], turn_callback, conversation_history, nil)
            
            # Save assistant response to DB
            save_benchmark_message('assistant', turn_response, session_id) if turn_response.present?
            conversation_history << { role: 'assistant', content: turn_response }
            
            log "Turn #{idx + 1} complete. Response: #{turn_response.length} chars", level: :debug
          end
        end
      else
        log "Request: \"#{task[:request].truncate(80)}\"", level: :info
        scout.process_message_with_tools_streaming(task[:request], callback, [], nil)
      end

      log "Execution complete. #{tool_calls} tool calls, #{response_text.length} chars response", level: :success

      {
        response: response_text,
        tool_calls: tool_calls,
        tools_used: tools_used.uniq,
        canvas_loaded: canvas_loaded,
        errors: errors
      }
    rescue => e
      log "EXCEPTION: #{e.message}", level: :error
      log e.backtrace.first(3).join("\n"), level: :debug if verbose?
      {
        response: nil,
        tool_calls: 0,
        tools_used: [],
        errors: [e.message]
      }
    end

    # ============================================
    # SETUP HELPERS
    # ============================================

    # Create a single test contact with specific attributes
    def create_test_contact(lifecycle_stage: 'lead', email: nil, **attrs)
      email ||= "benchmark_#{SecureRandom.hex(4)}@test.com"
      Contact.create!(
        entity: @entity,
        user: @user,
        first_name: attrs[:first_name] || "Benchmark",
        last_name: attrs[:last_name] || lifecycle_stage.titleize,
        email: email,
        status: 'active',
        lifecycle_stage: lifecycle_stage
      )
    end

    # Save message to DB like the real controller does
    # This enables UnifiedMemory to work properly in multi-turn benchmarks
    def save_benchmark_message(role, content, session_id)
      return if content.blank?
      
      ScoutMessage.create!(
        user_id: @user.id,
        entity_id: @entity.id,
        session_id: session_id,
        role: role,
        content: content,
        metadata: { benchmark: true },
        memory_layer: 'l1'
      )
    rescue => e
      log "Failed to save benchmark message: #{e.message}", level: :warning
    end

    def ensure_contacts(count, lifecycle_stages: nil)
      existing = Contact.where(entity: @entity).count
      needed = count - existing
      return if needed <= 0

      # Valid values:
      # - status: active, inactive, unsubscribed, bounced
      # - lifecycle_stage: subscriber, lead, mql, sql, opportunity, customer, evangelist
      lifecycle_stages ||= ['lead']

      needed.times do |i|
        Contact.create!(
          entity: @entity,
          user: @user,  # Required!
          first_name: "Benchmark",
          last_name: "Contact#{existing + i}",
          email: "benchmark#{existing + i}@test.com",
          status: 'active',  # Valid status
          lifecycle_stage: lifecycle_stages.sample
        )
      end
    end

    def ensure_campaigns(count)
      existing = Campaign.where(entity: @entity).count
      needed = count - existing
      return if needed <= 0

      needed.times do |i|
        Campaign.create!(
          entity: @entity,
          user: @user,
          name: "Benchmark Campaign #{existing + i}",
          status: 'draft'
        )
      end
    end

    def ensure_landing_pages(count)
      existing = LandingPage.where(entity: @entity).count
      needed = count - existing
      return if needed <= 0

      needed.times do |i|
        LandingPage.create!(
          entity: @entity,
          user: @user,
          title: "Benchmark Page #{existing + i}",
          slug: "benchmark-page-#{existing + i}",
          status: 'draft'
        )
      end
    end

    def create_failing_plan_step
      phases = [{
        id: 'phase_1',
        name: 'Test Phase',
        status: 'executing',
        steps: [{
          id: 'step_0',
          name: 'Failed Step',
          description: 'This step has failed',
          status: 'failed',
          error: 'Simulated failure for benchmark testing',
          agent: nil
        }]
      }]

      plan = ExecutionPlan.create!(
        entity: @entity,
        user: @user,
        title: 'Test Plan with Failure',
        original_request: 'Benchmark test plan',
        complexity: 'simple',
        status: 'executing',
        phases: phases,
        total_steps: 1
      )
      plan
    end

    # ============================================
    # REPORTING
    # ============================================

    def generate_report
      puts "=" * 80
      puts "📊 BOB v4.0 BENCHMARK RESULTS"
      puts "=" * 80
      puts ""

      total = @results.count
      passed = @results.count { |r| r[:passed] }
      avg_score = total > 0 ? (@results.sum { |r| r[:total_score] } / total).round(3) : 0

      puts "OVERALL: #{passed}/#{total} passed (#{(passed.to_f / [total, 1].max * 100).round(1)}%)"
      puts "Average Score: #{(avg_score * 100).round(1)}%"
      puts ""

      # Determine system classification
      classification = classify_system(avg_score)
      puts "SYSTEM CLASSIFICATION: #{classification}"
      puts ""

      # By Tier
      puts "BY TIER:"
      puts "-" * 40
      BusinessBenchmarkV4::DIFFICULTY_TIERS.each do |tier_key, tier_info|
        tier_results = @results.select { |r| r[:tier] == tier_key }
        next if tier_results.empty?

        tier_passed = tier_results.count { |r| r[:passed] }
        tier_avg = (tier_results.sum { |r| r[:total_score] } / tier_results.count).round(3)
        expected = (tier_info[:expected] * 100).round

        status = tier_passed >= (tier_results.count * tier_info[:expected] * 0.8) ? "✓" : "✗"
        puts "  #{status} #{tier_info[:name]}: #{tier_passed}/#{tier_results.count} (#{(tier_avg * 100).round(1)}%) [Expected: #{expected}%]"
      end
      puts ""

      # By Dimension
      puts "BY DIMENSION:"
      puts "-" * 40
      BusinessBenchmarkV4::SCORING_DIMENSIONS.each do |dim, config|
        dim_scores = @results.map { |r| r[:dimension_scores][dim] || 0.0 }
        avg = dim_scores.any? ? (dim_scores.sum / dim_scores.count).round(3) : 0
        puts "  #{dim.to_s.titleize}: #{(avg * 100).round(1)}%"
      end
      puts ""

      # Factory Results
      factory_results = @results.select { |r| r[:category].to_s.include?('factory') || r[:category] == :orchestration }
      if factory_results.any?
        puts "🏭 FACTORY INTEGRATION RESULTS:"
        puts "-" * 40
        factory_results.group_by { |r| r[:category] }.each do |cat, cat_results|
          cat_passed = cat_results.count { |r| r[:passed] }
          cat_avg = (cat_results.sum { |r| r[:total_score] } / cat_results.count).round(3)
          puts "  #{BusinessBenchmarkV4::CATEGORIES[cat] || cat}: #{cat_passed}/#{cat_results.count} (#{(cat_avg * 100).round(1)}%)"
        end
        puts ""
      end

      # Verification Breakdown
      puts "BY VERIFICATION TYPE:"
      puts "-" * 40
      @results.group_by { |r| r[:verification]&.dig(:type) }.each do |vtype, v_results|
        v_passed = v_results.count { |r| r[:verification]&.dig(:passed) }
        puts "  #{vtype}: #{v_passed}/#{v_results.count} verified"
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

      # Failures
      failures = @results.reject { |r| r[:passed] }
      if failures.any?
        puts "❌ FAILURES (#{failures.count}):"
        puts "-" * 40
        failures.each do |f|
          puts "  • #{f[:name]} (#{f[:tier]}) - Score: #{(f[:total_score] * 100).round}%"
          if f[:verification]
            puts "    Verification: #{f[:verification][:type]} - #{f[:verification][:passed] ? 'PASSED' : 'FAILED'}"
          end
          puts "    Errors: #{f[:errors].join(', ')}" if f[:errors]&.any?
        end
        puts ""
      end

      puts "=" * 80

      {
        total: total,
        passed: passed,
        avg_score: avg_score,
        classification: classification,
        results: @results
      }
    end

    def classify_system(avg_score)
      score_pct = avg_score * 100
      case score_pct
      when 90..100 then "🏆 WORLD CLASS (#{score_pct.round(1)}%)"
      when 75..90 then "⭐ EXPERT SYSTEM (#{score_pct.round(1)}%)"
      when 60..75 then "✅ EXCELLENT SYSTEM (#{score_pct.round(1)}%)"
      when 40..60 then "📊 GOOD SYSTEM (#{score_pct.round(1)}%)"
      when 20..40 then "⚠️ BASELINE SYSTEM (#{score_pct.round(1)}%)"
      else "❌ NEEDS IMPROVEMENT (#{score_pct.round(1)}%)"
      end
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

