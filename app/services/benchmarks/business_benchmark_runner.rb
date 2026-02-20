# frozen_string_literal: true

module Benchmarks
  # ============================================
  # Business Benchmark Runner
  # 
  # Runs the Business Operations Benchmark (BOB) v1.0
  # and scores responses on a 1-5 scale
  # 
  # Can run in isolated test mode (recommended for CI/regression)
  # or against a real entity (for production benchmarking)
  # ============================================
  class BusinessBenchmarkRunner
    attr_reader :entity, :user, :results, :run_id, :benchmark_run

    # Scoring criteria
    SCORE_DESCRIPTIONS = {
      1 => 'Completely misses the mark',
      2 => 'Partially addresses but major gaps',
      3 => 'Adequate but generic/incomplete',
      4 => 'Good, meets most rubric criteria',
      5 => 'Excellent, fully meets rubric with insight'
    }.freeze

    # Initialize with explicit entity/user or use test environment
    # @param entity [Entity] optional - uses TestEnvironment if nil
    # @param user [User] optional - uses TestEnvironment if nil  
    # @param use_test_env [Boolean] if true, uses isolated test environment
    # @param cleanup_before [Boolean] if true, cleans up test data before run
    def initialize(entity: nil, user: nil, use_test_env: false, cleanup_before: false)
      if use_test_env || (entity.nil? && user.nil?)
        @entity = TestEnvironment.entity
        @user = TestEnvironment.user
        @using_test_env = true
        
        if cleanup_before
          Rails.logger.info "[Benchmark] Cleaning up test environment before run..."
          TestEnvironment.cleanup!
        end
      else
        @entity = entity
        @user = user
        @using_test_env = false
      end
      
      @results = []
      @run_id = SecureRandom.uuid
    end

    # Check if running in isolated test environment
    def using_test_environment?
      @using_test_env
    end

    # Clean up test data (only works in test environment)
    def cleanup!
      raise "Cleanup only available in test environment" unless @using_test_env
      TestEnvironment.cleanup!
    end

    # Run a single task and get response
    # For creation tasks, also verifies the created assets
    def run_task(task, use_scout: true, verify_assets: true)
      start_time = Time.current
      task_start_time = Time.current # For finding created assets

      # Build the full prompt with scenario context
      full_prompt = build_prompt(task)

      begin
        if use_scout
          result = run_with_scout(full_prompt)
          response = result[:response]
          tool_calls = result[:tool_calls]
          agent_calls = result[:agent_calls]
          tools_used = result[:tools_used]
          agents_used = result[:agents_used]
          data_sources = result[:data_sources]
          delegated_jobs = result[:delegated_jobs] || []
          agent_results = result[:agent_results] || []
        else
          response = run_with_raw_llm(full_prompt)
          tool_calls = 0
          agent_calls = 0
          tools_used = []
          agents_used = []
          data_sources = []
          delegated_jobs = []
          agent_results = []
        end

        elapsed_ms = ((Time.current - start_time) * 1000).round

        task_result = {
          task_id: task[:id],
          category: task[:category],
          name: task[:name],
          response: response,
          elapsed_ms: elapsed_ms,
          success: true,
          rubric: task[:rubric],
          # Grounding metrics - helps verify answer isn't hallucinated
          tool_calls: tool_calls,
          agent_calls: agent_calls,
          tools_used: tools_used,
          agents_used: agents_used,
          data_sources: data_sources,
          grounded: tool_calls > 0 || agent_calls > 0,
          # Delegation tracking
          delegated_jobs: delegated_jobs,
          agent_results: agent_results
        }

        # ============================================
        # VERIFY CREATED ASSETS
        # For tasks that create things, check they actually exist and work
        # ============================================
        if verify_assets && use_scout
          created_assets = find_created_assets(since: task_start_time - 5.seconds)
          task_result[:created_assets] = created_assets

          # Verify agents
          if task[:creates_agent] && created_assets[:agents]&.any?
            agent_verifications = created_assets[:agents].map do |agent|
              verify_created_agent(agent[:slug])
            end
            task_result[:agent_verifications] = agent_verifications
            task_result[:agents_created] = created_assets[:agents].size
            task_result[:agents_verified] = agent_verifications.count { |v| v[:verified] }
          end

          # Verify tools
          if task[:creates_tool] && created_assets[:tools]&.any?
            tool_verifications = created_assets[:tools].map do |tool|
              verify_created_tool(tool[:name])
            end
            task_result[:tool_verifications] = tool_verifications
            task_result[:tools_created] = created_assets[:tools].size
            task_result[:tools_verified] = tool_verifications.count { |v| v[:verified] }
          end

          # Verify integrations
          if task[:creates_integration] && created_assets[:integrations]&.any?
            integration_verifications = created_assets[:integrations].map do |integration|
              verify_created_integration(integration[:name])
            end
            task_result[:integration_verifications] = integration_verifications
            task_result[:integrations_created] = created_assets[:integrations].size
            task_result[:integrations_verified] = integration_verifications.count { |v| v[:verified] }
            
            # Check if any integration was actually tested successfully
            task_result[:integrations_tested] = integration_verifications.count { |v| v[:test_executed] && v[:test_success] }
          end

          # Verify landing pages
          if task[:creates_asset] && created_assets[:landing_pages]&.any?
            page_verifications = created_assets[:landing_pages].map do |page|
              verify_created_landing_page(page[:id])
            end
            task_result[:landing_page_verifications] = page_verifications
            task_result[:landing_pages_created] = created_assets[:landing_pages].size
            task_result[:landing_pages_verified] = page_verifications.count { |v| v[:verified] }
          end

          # Verify email campaigns
          if task[:creates_asset] && created_assets[:email_campaigns]&.any?
            campaign_verifications = created_assets[:email_campaigns].map do |campaign|
              verify_created_email_campaign(campaign[:id])
            end
            task_result[:email_campaign_verifications] = campaign_verifications
            task_result[:email_campaigns_created] = created_assets[:email_campaigns].size
            task_result[:email_campaigns_verified] = campaign_verifications.count { |v| v[:verified] }
          end

          # Overall asset creation success
          if task[:creates_agent] || task[:creates_tool] || task[:creates_integration] || task[:creates_asset]
            total_expected = 0
            total_created = 0
            total_verified = 0

            total_expected += 1 if task[:creates_agent]
            total_created += task_result[:agents_created] || 0
            total_verified += task_result[:agents_verified] || 0

            total_expected += 1 if task[:creates_tool]
            total_created += task_result[:tools_created] || 0
            total_verified += task_result[:tools_verified] || 0

            total_expected += 1 if task[:creates_integration]
            total_created += task_result[:integrations_created] || 0
            total_verified += task_result[:integrations_verified] || 0

            total_expected += 1 if task[:creates_asset]
            total_created += (task_result[:landing_pages_created] || 0) + (task_result[:email_campaigns_created] || 0)
            total_verified += (task_result[:landing_pages_verified] || 0) + (task_result[:email_campaigns_verified] || 0)

            task_result[:creation_success] = total_created > 0
            task_result[:verification_success] = total_verified > 0
            task_result[:creation_summary] = {
              expected_types: total_expected,
              total_created: total_created,
              total_verified: total_verified
            }
          end
        end

        # ============================================
        # EMIT REWARD SIGNAL TO AGENT LIGHTNING
        # ============================================
        emit_benchmark_reward(task, task_result)

        task_result
      rescue => e
        Rails.logger.error "[BusinessBenchmark] Task #{task[:id]} failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        {
          task_id: task[:id],
          category: task[:category],
          name: task[:name],
          response: nil,
          elapsed_ms: ((Time.current - start_time) * 1000).round,
          success: false,
          error: e.message,
          rubric: task[:rubric],
          tool_calls: 0,
          agent_calls: 0,
          tools_used: [],
          agents_used: [],
          data_sources: [],
          grounded: false
        }
      end
    end

    # Run multiple tasks
    def run_tasks(tasks, use_scout: true, progress_callback: nil)
      tasks.each_with_index do |task, idx|
        progress_callback&.call(idx + 1, tasks.size, task[:name])
        result = run_task(task, use_scout: use_scout)
        @results << result
        sleep(0.3) # Rate limiting
      end
      @results
    end

    # Run full benchmark (all 100 tasks)
    def run_full_benchmark(use_scout: true)
      puts "\n" + "=" * 70
      puts "🏢 BUSINESS OPERATIONS BENCHMARK (BOB) v1.0"
      puts "=" * 70
      puts "Running #{BusinessBenchmark.all_tasks.size} tasks across #{BusinessBenchmark::CATEGORIES.size} categories"
      puts "Mode: #{use_scout ? 'AMOS (Scout)' : 'Raw Claude'}"
      puts "=" * 70
      puts ""

      BusinessBenchmark::CATEGORIES.each do |category_key, category_name|
        tasks = BusinessBenchmark.tasks_by_category(category_key)
        puts "📁 #{category_name} (#{tasks.size} tasks)"
        
        tasks.each_with_index do |task, idx|
          print "  #{idx + 1}. #{task[:name].truncate(40)}... "
          result = run_task(task, use_scout: use_scout)
          @results << result
          puts result[:success] ? "✓ (#{result[:elapsed_ms]}ms)" : "✗"
          sleep(0.3)
        end
        puts ""
      end

      generate_report
    end

    # Run quick benchmark (sample from each category)
    def run_quick_benchmark(tasks_per_category: 2, use_scout: true)
      puts "\n" + "=" * 70
      puts "⚡ QUICK BUSINESS BENCHMARK"
      puts "=" * 70
      puts "Running #{tasks_per_category} tasks per category (#{tasks_per_category * 10} total)"
      puts "Mode: #{use_scout ? 'AMOS (Scout)' : 'Raw Claude'}"
      puts "=" * 70
      puts ""

      BusinessBenchmark::CATEGORIES.each do |category_key, category_name|
        tasks = BusinessBenchmark.tasks_by_category(category_key).sample(tasks_per_category)
        puts "📁 #{category_name}"
        
        tasks.each do |task|
          print "  • #{task[:name].truncate(50)}... "
          result = run_task(task, use_scout: use_scout)
          @results << result
          puts result[:success] ? "✓" : "✗"
          sleep(0.3)
        end
      end
      puts ""

      generate_report
    end

    # Run comparison: Raw LLM vs AMOS
    def run_comparison(tasks_per_category: 1)
      puts "\n" + "=" * 70
      puts "🔬 BUSINESS BENCHMARK: Raw Claude vs AMOS"
      puts "=" * 70
      puts ""

      # Select sample tasks
      sample_tasks = []
      BusinessBenchmark::CATEGORIES.each_key do |category_key|
        sample_tasks += BusinessBenchmark.tasks_by_category(category_key).sample(tasks_per_category)
      end

      puts "Testing #{sample_tasks.size} tasks..."
      puts ""

      # Run with raw LLM
      puts "📊 Phase 1: RAW CLAUDE (no tools)"
      puts "-" * 50
      raw_results = []
      sample_tasks.each_with_index do |task, idx|
        print "  #{idx + 1}/#{sample_tasks.size}: #{task[:name].truncate(40)}... "
        result = run_task(task, use_scout: false)
        raw_results << result
        puts result[:success] ? "✓" : "✗"
        sleep(0.3)
      end
      puts ""

      # Run with AMOS
      puts "📊 Phase 2: AMOS (Scout with tools)"
      puts "-" * 50
      amos_results = []
      sample_tasks.each_with_index do |task, idx|
        print "  #{idx + 1}/#{sample_tasks.size}: #{task[:name].truncate(40)}... "
        result = run_task(task, use_scout: true)
        amos_results << result
        puts result[:success] ? "✓" : "✗"
        sleep(0.3)
      end
      puts ""

      # Summary
      raw_success = raw_results.count { |r| r[:success] }
      amos_success = amos_results.count { |r| r[:success] }
      raw_avg_time = raw_results.filter { |r| r[:success] }.map { |r| r[:elapsed_ms] }.sum / [raw_success, 1].max
      amos_avg_time = amos_results.filter { |r| r[:success] }.map { |r| r[:elapsed_ms] }.sum / [amos_success, 1].max

      puts "=" * 70
      puts "📊 COMPARISON RESULTS"
      puts "=" * 70
      puts ""
      puts "| System | Success | Avg Time |"
      puts "|--------|---------|----------|"
      puts "| Raw Claude | #{raw_success}/#{sample_tasks.size} | #{raw_avg_time}ms |"
      puts "| AMOS (Scout) | #{amos_success}/#{sample_tasks.size} | #{amos_avg_time}ms |"
      puts ""
      puts "Note: Quality scoring requires manual review of responses."
      puts "Run 'rake benchmark:business:export' to export responses for scoring."
      puts "=" * 70

      {
        raw: raw_results,
        amos: amos_results,
        sample_tasks: sample_tasks
      }
    end

    # Generate summary report
    def generate_report
      puts "=" * 70
      puts "📊 BENCHMARK RESULTS"
      puts "=" * 70
      puts ""

      # Overall stats
      total = @results.size
      successful = @results.count { |r| r[:success] }
      avg_time = @results.filter { |r| r[:success] }.map { |r| r[:elapsed_ms] }.sum / [successful, 1].max

      puts "Overall: #{successful}/#{total} tasks completed (#{(successful.to_f / total * 100).round(1)}%)"
      puts "Average response time: #{avg_time}ms"
      puts ""

      # Tool & Agent Usage (Grounding metrics)
      total_tool_calls = @results.sum { |r| r[:tool_calls] || 0 }
      total_agent_calls = @results.sum { |r| r[:agent_calls] || 0 }
      grounded_count = @results.count { |r| r[:grounded] }
      
      all_tools = @results.flat_map { |r| r[:tools_used] || [] }.compact
      tool_frequency = all_tools.tally.sort_by { |_, v| -v }
      
      puts "🔧 Tool & Agent Usage (Grounding Metrics):"
      puts "  Total tool calls: #{total_tool_calls}"
      puts "  Total agent calls: #{total_agent_calls}"
      puts "  Tasks using tools/agents: #{grounded_count}/#{total} (#{(grounded_count.to_f / [total, 1].max * 100).round(1)}%)"
      
      # Asset Creation Stats
      creation_results = @results.select { |r| r[:creation_summary].present? }
      if creation_results.any?
        puts ""
        puts "🏗️  Asset Creation (Agents/Tools/Integrations/Pages):"
        
        total_created = creation_results.sum { |r| r[:creation_summary][:total_created] || 0 }
        total_verified = creation_results.sum { |r| r[:creation_summary][:total_verified] || 0 }
        creation_tasks = creation_results.size
        successful_creations = creation_results.count { |r| r[:creation_success] }
        verified_creations = creation_results.count { |r| r[:verification_success] }
        
        puts "  Creation tasks: #{creation_tasks}"
        puts "  Assets created: #{total_created}"
        puts "  Assets verified working: #{total_verified}"
        puts "  Creation success rate: #{(successful_creations.to_f / [creation_tasks, 1].max * 100).round(1)}%"
        puts "  Verification success rate: #{(verified_creations.to_f / [creation_tasks, 1].max * 100).round(1)}%"
        
        # Breakdown by type
        agents_created = @results.sum { |r| r[:agents_created] || 0 }
        agents_verified = @results.sum { |r| r[:agents_verified] || 0 }
        tools_created = @results.sum { |r| r[:tools_created] || 0 }
        tools_verified = @results.sum { |r| r[:tools_verified] || 0 }
        integrations_created = @results.sum { |r| r[:integrations_created] || 0 }
        integrations_verified = @results.sum { |r| r[:integrations_verified] || 0 }
        integrations_tested = @results.sum { |r| r[:integrations_tested] || 0 }
        pages_created = @results.sum { |r| r[:landing_pages_created] || 0 }
        pages_verified = @results.sum { |r| r[:landing_pages_verified] || 0 }
        campaigns_created = @results.sum { |r| r[:email_campaigns_created] || 0 }
        campaigns_verified = @results.sum { |r| r[:email_campaigns_verified] || 0 }
        
        puts ""
        puts "  By Type:"
        puts "    Agents: #{agents_created} created, #{agents_verified} verified" if agents_created > 0
        puts "    Tools: #{tools_created} created, #{tools_verified} verified" if tools_created > 0
        puts "    Integrations: #{integrations_created} created, #{integrations_verified} verified, #{integrations_tested} tested" if integrations_created > 0
        puts "    Landing Pages: #{pages_created} created, #{pages_verified} verified" if pages_created > 0
        puts "    Email Campaigns: #{campaigns_created} created, #{campaigns_verified} verified" if campaigns_created > 0
      end
      
      if tool_frequency.any?
        puts ""
        puts "  Most used tools:"
        tool_frequency.first(5).each do |tool, count|
          puts "    #{tool}: #{count} calls"
        end
      end
      puts ""

      # By category with grounding
      puts "By Category:"
      BusinessBenchmark::CATEGORIES.each do |category_key, category_name|
        category_results = @results.select { |r| r[:category] == category_key }
        next if category_results.empty?

        success = category_results.count { |r| r[:success] }
        total_cat = category_results.size
        cat_tool_calls = category_results.sum { |r| r[:tool_calls] || 0 }
        cat_grounded = category_results.count { |r| r[:grounded] }
        
        grounded_indicator = cat_grounded > 0 ? "🔧#{cat_grounded}" : "📝"
        puts "  #{category_name}: #{success}/#{total_cat} #{grounded_indicator}"
      end

      puts ""
      puts "Legend: 🔧N = N tasks used tools/agents, 📝 = pure LLM response"
      puts ""
      puts "=" * 70
      puts "⚠️  GROUNDING WARNING:"
      if grounded_count == 0
        puts "   No tasks used tools or agents - responses may be hallucinated!"
        puts "   Consider tasks that require real data (CRM queries, web search, etc.)"
      elsif grounded_count < total / 2
        puts "   Only #{grounded_count}/#{total} tasks used external data sources."
        puts "   Ungrounded responses should be manually verified."
      else
        puts "   #{grounded_count}/#{total} tasks used tools/agents for grounding."
      end
      puts ""
      puts "Quality scoring (1-5) requires manual review."
      puts "Export results with: rake benchmark:business:export"
      puts "=" * 70

      {
        total: total,
        successful: successful,
        avg_time_ms: avg_time,
        total_tool_calls: total_tool_calls,
        total_agent_calls: total_agent_calls,
        grounded_tasks: grounded_count,
        tool_frequency: tool_frequency.to_h,
        results: @results
      }
    end

    # Export results for manual scoring
    def export_for_scoring(filename = nil)
      filename ||= "business_benchmark_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      filepath = Rails.root.join('tmp', 'benchmarks', filename)
      FileUtils.mkdir_p(File.dirname(filepath))

      export_data = {
        benchmark: 'Business Operations Benchmark v1.0',
        run_at: Time.current.iso8601,
        entity: @entity.name,
        total_tasks: @results.size,
        scoring_guide: SCORE_DESCRIPTIONS,
        results: @results.map do |r|
          task = BusinessBenchmark.task(r[:task_id])
          {
            task_id: r[:task_id],
            category: r[:category],
            name: r[:name],
            scenario: task[:scenario],
            request: task[:request],
            rubric: r[:rubric],
            response: r[:response],
            elapsed_ms: r[:elapsed_ms],
            success: r[:success],
            score: nil, # To be filled in manually
            notes: nil  # For reviewer notes
          }
        end
      }

      File.write(filepath, JSON.pretty_generate(export_data))
      puts "Exported to: #{filepath}"
      filepath
    end

    private

    def emit_benchmark_reward(task, task_result)
      # Agent Lightning system has been deprecated and removed.
      # Benchmark rewards are now tracked via DecisionTrace and TaskExperience.
    end

    # Calculate reward value (0.0 to 1.0) based on task result
    def calculate_benchmark_reward(task, result)
      return 0.0 unless result[:success]

      score = 0.5  # Base score for task completion

      # Bonus for using tools when required
      if task[:requires_tools] || task[:grounding_required]
        score += 0.15 if result[:grounded]
      else
        score += 0.1  # Small bonus for non-tool tasks
      end

      # Bonus for successful asset creation
      if task[:creates_agent] || task[:creates_tool] || task[:creates_integration] || task[:creates_asset]
        score += 0.15 if result[:creation_success]
        score += 0.1 if result[:verification_success]
      end

      # Bonus for agent delegation when expected
      if task[:expected_agent].present?
        score += 0.1 if result[:agent_calls].to_i > 0
      end

      # Penalty for very slow responses (>60s)
      if result[:elapsed_ms].to_i > 60_000
        score -= 0.05
      end

      # Bonus for fast responses (<10s)
      if result[:elapsed_ms].to_i < 10_000
        score += 0.05
      end

      # Clamp to 0.0-1.0
      [[score, 0.0].max, 1.0].min
    end

    def build_prompt(task)
      <<~PROMPT
        You are Amos, a business assistant helping a small/medium business owner.
        
        **Context/Scenario:**
        #{task[:scenario]}
        
        **Request:**
        #{task[:request]}
        
        Please provide a practical, actionable response. Be specific and avoid generic advice.
      PROMPT
    end

    def run_with_scout(prompt)
      session_id = "benchmark_#{SecureRandom.hex(4)}"
      
      Rails.logger.info "[Benchmark] Starting Scout session: #{session_id}"
      Rails.logger.info "[Benchmark] Entity: #{@entity.name} (ID: #{@entity.id})"
      Rails.logger.info "[Benchmark] User: #{@user.email} (ID: #{@user.id})"
      
      begin
        scout = V3::AgentLoop # V3 migration stub.new(@user, @entity, session_id)
      rescue => e
        Rails.logger.error "[Benchmark] Failed to initialize Scout: #{e.message}"
        return {
          response: nil,
          tool_calls: 0,
          agent_calls: 0,
          tools_used: [],
          agents_used: [],
          data_sources: [],
          delegated_jobs: [],
          agent_results: [],
          error: "Scout initialization failed: #{e.message}"
        }
      end

      response_text = ""
      tool_call_log = []
      delegated_job_ids = []
      chunk_count = 0
      
      # Robust callback that captures all relevant data
      callback = ->(chunk) { 
        chunk_count += 1
        
        begin
          if chunk.is_a?(String)
            response_text += chunk
          elsif chunk.is_a?(Hash)
            # Track tool calls from streaming chunks
            # Handle both string and symbol keys
            chunk_type = (chunk[:type] || chunk['type']).to_s
            
            # Capture tool starts
            if chunk_type == 'tool_start'
              tool_name = chunk[:tool_name] || chunk[:name] || chunk['tool_name'] || chunk['name']
              if tool_name.present?
                Rails.logger.debug "[Benchmark] Tool start: #{tool_name}"
                tool_call_log << {
                  name: tool_name,
                  type: :tool,
                  timestamp: Time.current
                }
              end
            end
            
            # Capture tool completions (more reliable for tool names)
            if chunk_type == 'tool_complete'
              tool_name = chunk[:name] || chunk['name']
              if tool_name.present? && !tool_call_log.any? { |t| t[:name] == tool_name }
                Rails.logger.debug "[Benchmark] Tool complete: #{tool_name}"
                tool_call_log << {
                  name: tool_name,
                  type: :tool,
                  timestamp: Time.current
                }
              end
            end
            
            # Track delegated agent jobs - THIS IS CRITICAL
            if chunk_type == 'agent_delegated'
              job_id = chunk[:job_id] || chunk['job_id']
              agent_name = chunk[:agent] || chunk['agent']
              
              if job_id
                Rails.logger.info "[Benchmark] 🎯 CAPTURED delegated job: #{job_id} to #{agent_name}"
                delegated_job_ids << job_id
              else
                Rails.logger.warn "[Benchmark] ⚠️ agent_delegated chunk without job_id: #{chunk.inspect}"
              end
            end
            
            # Capture content chunks
            if chunk_type == 'content_chunk'
              content = chunk[:content] || chunk['content']
              response_text += content if content.present?
            end
          end
        rescue => e
          Rails.logger.error "[Benchmark] Callback error on chunk #{chunk_count}: #{e.message}"
        end
      }

      # Call Scout with streaming
      Rails.logger.info "[Benchmark] Calling Scout process_message_with_tools_streaming..."
      
      begin
        result = scout.process_message_with_tools_streaming(
          prompt,
          callback,
          [],
          nil
        )
      rescue => e
        Rails.logger.error "[Benchmark] Scout streaming failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        return {
          response: response_text.presence,
          tool_calls: tool_call_log.size,
          agent_calls: 0,
          tools_used: tool_call_log.map { |t| t[:name] }.compact.uniq,
          agents_used: [],
          data_sources: [],
          delegated_jobs: delegated_job_ids,
          agent_results: [],
          error: "Scout streaming failed: #{e.message}"
        }
      end
      
      Rails.logger.info "[Benchmark] Scout returned. Chunks received: #{chunk_count}"
      Rails.logger.info "[Benchmark] Tool call log: #{tool_call_log.map { |t| t[:name] }.inspect}"
      Rails.logger.info "[Benchmark] Delegated jobs from callback: #{delegated_job_ids.inspect}"

      # Extract final response and tool usage from result
      response = nil
      tools_used = []
      agents_used = []
      data_sources = []
      
      if result.is_a?(Hash)
        Rails.logger.debug "[Benchmark] Result keys: #{result.keys.inspect}"
        
        final = result[:final_response] || result['final_response'] || {}
        response = final[:message] || final['message'] || result[:message] || response_text
        
        # Extract tool usage from result metadata
        tool_results = result[:tool_results] || result[:tools_executed] || []
        if tool_results.any?
          Rails.logger.debug "[Benchmark] Processing #{tool_results.size} tool results"
          
          tool_results.each do |tr|
            tool_name = tr[:name] || tr[:tool_name] || tr['name'] || tr['tool_name']
            tools_used << tool_name if tool_name
            
            # Track data sources
            if tool_name&.include?('get_data') || tool_name&.include?('query')
              data_sources << { type: 'database', tool: tool_name }
            elsif tool_name&.include?('web_search')
              data_sources << { type: 'web_search', tool: tool_name }
            elsif tool_name&.include?('read_document')
              data_sources << { type: 'document', tool: tool_name }
            end
            
            # Track agent delegations and capture job IDs from result
            if tool_name&.include?('delegate') || tool_name&.include?('invoke_agent') || tool_name&.include?('ask_agent')
              tr_result = tr[:result] || tr['result'] || {}
              agent_slug = tr_result[:agent] || tr_result['agent'] || 
                          tr_result[:agent_type] || tr_result['agent_type'] || 
                          tr[:arguments]&.dig(:agent_type) || 'unknown'
              agents_used << agent_slug
              
              # Capture job ID from delegation result (backup to callback)
              job_id = tr_result[:job_id] || tr_result['job_id']
              if job_id && !delegated_job_ids.include?(job_id)
                Rails.logger.info "[Benchmark] 🎯 CAPTURED job_id from result: #{job_id}"
                delegated_job_ids << job_id
              end
            end
          end
        end
        
        # Also check for tools_used in result
        if result[:tools_used].is_a?(Array)
          tools_used = (tools_used + result[:tools_used]).uniq
        end
        
        # Check if delegation occurred flag is set
        if result[:delegation_occurred]
          Rails.logger.info "[Benchmark] Delegation occurred flag is true"
        end
      else
        response = result.to_s.presence || response_text
      end
      
      # Add any tools from the streaming log
      tool_call_log.each do |tc|
        tools_used << tc[:name] if tc[:name] && !tools_used.include?(tc[:name])
      end
      
      tools_used = tools_used.compact.uniq
      agents_used = agents_used.compact.uniq
      delegated_job_ids = delegated_job_ids.compact.uniq
      
      Rails.logger.info "[Benchmark] Final tools_used: #{tools_used.inspect}"
      Rails.logger.info "[Benchmark] Final agents_used: #{agents_used.inspect}"
      Rails.logger.info "[Benchmark] Final delegated_job_ids: #{delegated_job_ids.inspect}"

      # ============================================
      # WAIT FOR DELEGATED AGENT JOBS TO COMPLETE
      # ============================================
      agent_results = []
      if delegated_job_ids.any?
        Rails.logger.info "[Benchmark] ⏳ Waiting for #{delegated_job_ids.size} delegated jobs to complete..."
        
        delegated_job_ids.each do |job_id|
          Rails.logger.info "[Benchmark] Waiting for job #{job_id}..."
          agent_result = wait_for_agent_completion(job_id)
          agent_results << agent_result
          
          Rails.logger.info "[Benchmark] Job #{job_id} result: success=#{agent_result[:success]}, status=#{agent_result[:status]}"
          
          # Append agent's response to the main response
          if agent_result[:success] && agent_result[:output].present?
            response = [response, "\n\n---\n**Agent Result:**\n#{agent_result[:output]}"].compact.join
            agents_used << agent_result[:agent_slug] if agent_result[:agent_slug]
          elsif !agent_result[:success]
            Rails.logger.warn "[Benchmark] Job #{job_id} failed: #{agent_result[:error]}"
          end
        end
        
        Rails.logger.info "[Benchmark] ✅ All delegated jobs processed"
      else
        # No jobs captured from callback - check if we should look for recent executions
        # This is a fallback for cases where the callback didn't capture the job_id
        if tools_used.any? { |t| t&.include?('delegate') || t&.include?('invoke_agent') }
          Rails.logger.warn "[Benchmark] ⚠️ Delegation tool used but no job_id captured - checking recent executions..."
          
          recent_execution = AgentPluginExecution
            .where(user: @user)
            .where('created_at > ?', 30.seconds.ago)
            .order(created_at: :desc)
            .first
          
          if recent_execution
            Rails.logger.info "[Benchmark] Found recent execution: #{recent_execution.id} (#{recent_execution.agent_plugin&.slug})"
            delegated_job_ids << recent_execution.id
            
            agent_result = wait_for_agent_completion(recent_execution.id)
            agent_results << agent_result
            
            if agent_result[:success] && agent_result[:output].present?
              response = [response, "\n\n---\n**Agent Result:**\n#{agent_result[:output]}"].compact.join
              agents_used << agent_result[:agent_slug] if agent_result[:agent_slug]
            end
          end
        end
      end
      
      {
        response: response,
        tool_calls: tools_used.size,
        agent_calls: agents_used.size,
        tools_used: tools_used,
        agents_used: agents_used.uniq,
        data_sources: data_sources,
        delegated_jobs: delegated_job_ids,
        agent_results: agent_results
      }
    end

    # Wait for a delegated agent job to complete
    # Returns the execution result or times out after max_wait_seconds
    # Default 5 minutes - agent tasks can take a while especially for complex integrations
    def wait_for_agent_completion(execution_id, max_wait_seconds: 300, poll_interval: 3)
      start_time = Time.current
      
      loop do
        execution = AgentPluginExecution.find_by(id: execution_id)
        
        unless execution
          return { success: false, error: "Execution #{execution_id} not found" }
        end
        
        case execution.status
        when 'completed'
          output = execution.output_result
          output_text = if output.is_a?(Hash)
            output['response'] || output['result'] || output['message'] || output.to_json
          else
            output.to_s
          end
          
          return {
            success: true,
            execution_id: execution_id,
            agent_slug: execution.agent_plugin&.slug,
            output: output_text,
            duration_ms: execution.duration_ms,
            status: 'completed'
          }
          
        when 'failed', 'error'
          error_msg = execution.output_result&.dig('error') || execution.output_result&.dig(:error) || 'Unknown error'
          return {
            success: false,
            execution_id: execution_id,
            agent_slug: execution.agent_plugin&.slug,
            error: error_msg,
            status: execution.status
          }
          
        when 'running', 'pending', 'queued'
          # Still running, check timeout
          elapsed = Time.current - start_time
          if elapsed > max_wait_seconds
            return {
              success: false,
              execution_id: execution_id,
              agent_slug: execution.agent_plugin&.slug,
              error: "Timeout after #{max_wait_seconds}s",
              status: 'timeout'
            }
          end
          
          # Wait and poll again
          sleep(poll_interval)
          
        else
          # Unknown status
          return {
            success: false,
            execution_id: execution_id,
            error: "Unknown status: #{execution.status}",
            status: execution.status
          }
        end
      end
    end

    # ============================================
    # ASSET VERIFICATION METHODS
    # These test that created assets actually work
    # ============================================

    # Verify a newly created agent by running a test task
    def verify_created_agent(agent_slug, test_prompt: nil)
      agent = AgentPlugin.find_by(slug: agent_slug, entity: @entity)
      return { verified: false, error: "Agent '#{agent_slug}' not found" } unless agent

      test_prompt ||= "Hello, please introduce yourself and explain what you can do."
      
      begin
        # Create a test execution
        execution = AgentPluginExecution.create!(
          agent_plugin: agent,
          user: @user,
          entity: @entity,
          status: 'running',
          started_at: Time.current,
          input_context: { task: test_prompt, benchmark_test: true }
        )

        # Run the agent
        agent_instance = agent.instantiate(entity: @entity, user: @user, execution: execution)
        result = agent_instance.run(test_prompt, { entity: @entity, user: @user, execution: execution })

        execution.update!(
          status: 'completed',
          completed_at: Time.current,
          output_result: { response: result }
        )

        {
          verified: true,
          agent_id: agent.id,
          agent_slug: agent.slug,
          agent_name: agent.name,
          test_response: result.to_s.truncate(500),
          execution_id: execution.id
        }
      rescue => e
        {
          verified: false,
          agent_slug: agent_slug,
          error: e.message
        }
      end
    end

    # Verify a newly created tool by executing it
    def verify_created_tool(tool_name, test_args: {})
      tool_def = ToolDefinition.find_by(name: tool_name, entity: @entity) ||
                 ToolDefinition.find_by(name: tool_name, created_by: @user)
      
      return { verified: false, error: "Tool '#{tool_name}' not found" } unless tool_def

      begin
        # Get the tool catalog and execute
        catalog = Tools::ToolCatalog.instance
        tool_instance = catalog.get_tool(tool_name, user: @user, entity: @entity)
        
        if tool_instance
          result = tool_instance.execute(test_args)
          {
            verified: true,
            tool_id: tool_def.id,
            tool_name: tool_def.name,
            execution_type: tool_def.execution_type,
            test_result: result.to_s.truncate(500),
            success: !result.is_a?(Hash) || result[:error].blank?
          }
        else
          # For definition-based tools, try to execute via the definition
          result = tool_def.execute(test_args, user: @user, entity: @entity)
          {
            verified: true,
            tool_id: tool_def.id,
            tool_name: tool_def.name,
            execution_type: tool_def.execution_type,
            test_result: result.to_s.truncate(500),
            success: !result.is_a?(Hash) || result[:error].blank?
          }
        end
      rescue => e
        {
          verified: false,
          tool_name: tool_name,
          error: e.message
        }
      end
    end

    # Verify a newly created integration by testing an endpoint
    def verify_created_integration(integration_name, test_operation: nil)
      # Find integration - check entity-scoped, user-created, or recently created global
      integration = Integration.where(entity_id: @entity.id)
                               .or(Integration.where(created_by_id: @user.id))
                               .find_by(name: integration_name) ||
                    Integration.where(entity_id: @entity.id)
                               .or(Integration.where(created_by_id: @user.id))
                               .where("name ILIKE ?", "%#{integration_name}%").first ||
                    # Also check global integrations (entity_id is null) - for backwards compatibility
                    Integration.where(entity_id: nil).find_by(name: integration_name) ||
                    Integration.where(entity_id: nil).where("name ILIKE ?", "%#{integration_name}%").first
      
      return { verified: false, error: "Integration '#{integration_name}' not found" } unless integration

      begin
        # Check if integration has auth configured (or doesn't need it)
        needs_no_auth = integration.no_auth? || integration.auth_type == 'no_auth'
        has_auth = integration.auth_config.present? && 
                   (integration.auth_config['api_key'].present? || 
                    integration.auth_config['token'].present? ||
                    integration.auth_config['oauth_token'].present?)

        # Get available operations from integration_operations association
        operations = integration.integration_operations.map do |op|
          { 'name' => op.name, 'method' => op.http_method, 'path' => op.path_template }
        end
        
        # Try to execute a test operation if specified or pick the first GET
        test_op = if test_operation
          operations.find { |op| op['name'] == test_operation || op['path'] == test_operation }
        else
          operations.find { |op| op['method']&.upcase == 'GET' } || operations.first
        end

        result = {
          verified: true,
          integration_id: integration.id,
          integration_name: integration.name,
          base_url: integration.api_base_url,
          auth_configured: has_auth || needs_no_auth,
          auth_type: integration.auth_type,
          operations_count: operations.size,
          operations: operations.map { |op| "#{op['method']} #{op['path']}" }.first(5)
        }

        # If we have a test operation, try to call it
        # Even if auth isn't configured, some APIs (like JSONPlaceholder) don't need it
        if test_op
          begin
            # Try a direct HTTP call for GET operations to verify the integration works
            if test_op['method']&.upcase == 'GET'
              require 'net/http'
              path = test_op['path'].gsub(/\{[^}]+\}/, '1') # Replace path params with '1'
              uri = URI("#{integration.api_base_url}#{path}")
              response = Net::HTTP.get_response(uri)
              
              result[:test_executed] = true
              result[:test_success] = response.code.to_i < 400
              result[:test_response] = "HTTP #{response.code}: #{response.body.to_s.truncate(200)}"
              result[:test_method] = 'direct_http'
            else
              # For non-GET, try the execute_integration tool
              tool = Tools::ExecuteIntegrationTool.new(user: @user, entity: @entity)
              test_result = tool.execute({
                'integration_name' => integration.name,
                'operation' => test_op['name'] || test_op['path'],
                'params' => {}
              })
              
              result[:test_executed] = true
              result[:test_success] = test_result[:success] || test_result['success']
              result[:test_response] = test_result.to_s.truncate(300)
              result[:test_method] = 'tool_execution'
            end
          rescue => e
            result[:test_executed] = true
            result[:test_success] = false
            result[:test_error] = e.message
          end
        else
          result[:test_executed] = false
          result[:test_reason] = "No operations defined"
        end

        result
      rescue => e
        {
          verified: false,
          integration_name: integration_name,
          error: e.message
        }
      end
    end

    # Verify a created landing page
    def verify_created_landing_page(page_id_or_title)
      page = if page_id_or_title.is_a?(Integer)
        LandingPage.find_by(id: page_id_or_title, entity: @entity)
      else
        LandingPage.where("title ILIKE ?", "%#{page_id_or_title}%").where(entity: @entity).order(created_at: :desc).first
      end

      return { verified: false, error: "Landing page not found" } unless page

      content = page.html_content.to_s
      {
        verified: true,
        page_id: page.id,
        page_title: page.title,
        page_slug: page.slug,
        has_content: content.present?,
        content_length: content.length,
        has_hero: content.include?('hero') || content.downcase.include?('headline'),
        has_cta: content.downcase.include?('cta') || content.include?('button'),
        status: page.status,
        created_at: page.created_at
      }
    end

    # Verify a created email campaign
    def verify_created_email_campaign(campaign_id_or_name)
      campaign = if campaign_id_or_name.is_a?(Integer)
        Campaign.find_by(id: campaign_id_or_name, entity: @entity)
      else
        Campaign.where("name ILIKE ?", "%#{campaign_id_or_name}%").where(entity: @entity).order(created_at: :desc).first
      end

      return { verified: false, error: "Email campaign not found" } unless campaign

      {
        verified: true,
        campaign_id: campaign.id,
        campaign_name: campaign.name,
        has_template: campaign.email_template_id.present?,
        status: campaign.status,
        created_at: campaign.created_at
      }
    end

    # Find recently created assets after a benchmark task
    def find_created_assets(since:, types: [:agent, :tool, :integration, :landing_page, :email_campaign])
      assets = {}

      if types.include?(:agent)
        assets[:agents] = AgentPlugin.where(entity: @entity)
                                     .where('created_at > ?', since)
                                     .map { |a| { id: a.id, slug: a.slug, name: a.name } }
      end

      if types.include?(:tool)
        assets[:tools] = ToolDefinition.where(entity: @entity)
                                       .or(ToolDefinition.where(created_by: @user))
                                       .where('created_at > ?', since)
                                       .map { |t| { id: t.id, name: t.name, execution_type: t.execution_type } }
      end

      if types.include?(:integration)
        # Find integrations created for this entity, by this user, or recently created global ones
        assets[:integrations] = Integration.where(entity_id: @entity.id)
                                           .or(Integration.where(created_by_id: @user.id))
                                           .or(Integration.where(entity_id: nil)) # Include global for now
                                           .where('integrations.created_at > ?', since)
                                           .map { |i| { id: i.id, name: i.name, base_url: i.api_base_url } }
      end

      if types.include?(:landing_page) && defined?(LandingPage)
        assets[:landing_pages] = LandingPage.where(entity: @entity)
                                            .where('created_at > ?', since)
                                            .map { |p| { id: p.id, title: p.title, slug: p.slug } }
      end

      if types.include?(:email_campaign) && defined?(Campaign)
        assets[:email_campaigns] = Campaign.where(entity: @entity)
                                           .where('created_at > ?', since)
                                           .map { |c| { id: c.id, name: c.name, status: c.status } }
      end

      assets
    end

    def run_with_raw_llm(prompt)
      ai_service = BedrockService.new(user: @user, entity: @entity)

      response = ai_service.send_message(
        "You are Amos, a practical business assistant for SMB owners. Give specific, actionable advice.",
        [{ role: "user", content: prompt }],
        max_tokens: 2000,
        temperature: 0.7
      )

      response.is_a?(Hash) ? (response[:content] || response['content'] || response.to_s) : response.to_s
    end
  end
end

