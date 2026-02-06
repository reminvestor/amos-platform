# frozen_string_literal: true

module Collaboration
  # ============================================
  # System-Wide AMOS Platform Benchmark Runner
  # Executes comprehensive tests across all platform features
  # ============================================
  class SystemBenchmarkRunner
    attr_reader :entity, :user, :results, :start_time

    def initialize(entity:, user:)
      @entity = entity
      @user = user
      @results = []
      @start_time = nil
    end

    # ============================================
    # MAIN ENTRY POINTS
    # ============================================

    # Run all system benchmarks
    def run_full_suite(options = {})
      @start_time = Time.current
      @results = []

      verbose = options[:verbose] || false
      categories = options[:categories] || SystemBenchmarks.all_tests.keys

      puts "\n" + "=" * 60 if verbose
      puts "🚀 AMOS SYSTEM-WIDE BENCHMARK" if verbose
      puts "=" * 60 if verbose
      puts "Started: #{@start_time}" if verbose
      puts "Entity: #{@entity.name}" if verbose
      puts "Categories: #{categories.join(', ')}" if verbose
      puts "=" * 60 if verbose

      categories.each do |category|
        run_category(category, verbose: verbose)
      end

      generate_summary(verbose: verbose)
    end

    # Run quick validation (5-10 tests)
    def run_quick_validation(verbose: true)
      @start_time = Time.current
      @results = []

      tests = SystemBenchmarks.get_quick_tests

      puts "\n" + "=" * 60 if verbose
      puts "⚡ QUICK SYSTEM VALIDATION" if verbose
      puts "=" * 60 if verbose
      puts "Running #{tests.size} essential tests..." if verbose
      puts "" if verbose

      tests.each_with_index do |test, index|
        puts "#{index + 1}/#{tests.size}: #{test[:name]}" if verbose
        result = run_single_test(test)
        @results << result
        print_test_result(result) if verbose
      end

      generate_summary(verbose: verbose)
    end

    # Run a specific category
    def run_category(category, verbose: false)
      tests = SystemBenchmarks.get_tests(category)
      return if tests.empty?

      puts "\n📦 Category: #{category.to_s.upcase}" if verbose
      puts "-" * 40 if verbose

      tests.each do |test|
        # Skip tests with unmet requirements
        next if skip_test?(test)

        result = run_single_test(test)
        @results << result
        print_test_result(result) if verbose
      end
    end

    # Run a single test by ID
    def run_single_test_by_id(test_id)
      test = find_test_by_id(test_id)
      return { error: "Test '#{test_id}' not found" } unless test

      run_single_test(test)
    end

    # ============================================
    # TEST EXECUTION
    # ============================================

    def run_single_test(test)
      start_time = Time.current
      context = { entity: @entity, user: @user }

      begin
        # Execute the prompt through Scout
        response = execute_prompt(test[:prompt], timeout: test[:timeout_seconds] || 60)

        execution_time_ms = ((Time.current - start_time) * 1000).round

        # Check for execution errors
        if response[:error]
          return {
            test_id: test[:id],
            name: test[:name],
            category: test[:category],
            difficulty: test[:difficulty],
            passed: false,
            execution_time_ms: execution_time_ms,
            answer: nil,
            tokens_used: response[:tokens_used] || 0,
            error: response[:error]
          }
        end

        # Validate the result
        passed = validate_result(test, response, context)

        # Run cleanup if defined
        test[:cleanup]&.call(context)

        {
          test_id: test[:id],
          name: test[:name],
          category: test[:category],
          difficulty: test[:difficulty],
          passed: passed,
          execution_time_ms: execution_time_ms,
          answer: response[:answer]&.to_s&.truncate(200),
          tokens_used: response[:tokens_used] || 0,
          error: nil
        }

      rescue StandardError => e
        Rails.logger.error "[SystemBenchmark] Test #{test[:id]} failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")

        # Run cleanup even on failure
        test[:cleanup]&.call(context) rescue nil

        {
          test_id: test[:id],
          name: test[:name],
          category: test[:category],
          difficulty: test[:difficulty],
          passed: false,
          execution_time_ms: ((Time.current - start_time) * 1000).round,
          answer: nil,
          tokens_used: 0,
          error: "#{e.class}: #{e.message}"
        }
      end
    end

    private

    # ============================================
    # EXECUTION HELPERS
    # ============================================

    def execute_prompt(prompt, timeout: 60)
      Rails.logger.info "[SystemBenchmark] Using Scout V2 (main chat interface)"

      begin
        # Generate a unique session ID for this benchmark run
        session_id = "benchmark_#{SecureRandom.hex(8)}"
        
        # Use Scout V2 - the main chat interface with tools
        scout_service = V3::AgentLoop # V3 migration stub.new(@user, @entity, session_id)

        # Collect streaming output
        accumulated_response = ""
        tool_calls_made = false

        # Simple progress callback that collects the response
        progress_callback = ->(chunk) {
          if chunk.is_a?(String)
            accumulated_response += chunk
          end
        }

        # Run with timeout
        result = Timeout.timeout(timeout) do
          scout_service.process_message_with_tools_streaming(prompt, progress_callback, [], nil)
        end

        # Extract answer from result
        # Scout V2 returns { final_response: { message: "...", ... }, ... }
        answer = if result.is_a?(Hash)
          final = result[:final_response] || result['final_response'] || {}
          final[:message] || final['message'] || 
          result[:message] || result[:content] || accumulated_response
        else
          result.to_s.presence || accumulated_response
        end

        tool_calls_made = result.is_a?(Hash) && (result[:tool_calls_made] || result[:tools_used]&.any?)

        # Estimate tokens
        tokens = (prompt.length / 4) + (answer.to_s.length / 4)

        { answer: answer, tokens_used: tokens, delegated: tool_calls_made }

      rescue Timeout::Error
        { answer: nil, error: 'Timeout', tokens_used: 0 }
      rescue StandardError => e
        Rails.logger.error "[SystemBenchmark] Scout error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        raise e
      end
    end

    def extract_answer(result)
      return result if result.is_a?(String)
      
      if result.is_a?(Hash)
        # Scout returns :message from process_message_with_tools
        return result[:message] if result[:message].present?
        return result['message'] if result['message'].present?
        return result[:answer] if result[:answer].present?
        return result['answer'] if result['answer'].present?
        return result[:content] if result[:content].present?
        return result['content'] if result['content'].present?
        return result[:result] if result[:result].present?
        return result['result'] if result['result'].present?
      end
      
      result.to_s
    end

    def validate_result(test, response, context)
      return false if response[:error]
      return false if response[:answer].blank?

      validator = test[:validation]
      return true unless validator

      validator.call(response, context)
    rescue StandardError => e
      Rails.logger.error "[SystemBenchmark] Validation error for #{test[:id]}: #{e.message}"
      false
    end

    def skip_test?(test)
      # Skip if requires integration that doesn't exist
      if test[:requires_integration]
        begin
          return true unless Integration.exists?(slug: test[:requires_integration])
        rescue StandardError
          return true  # Skip if Integration table doesn't have expected columns
        end
      end

      # Skip if requires documents but none exist
      if test[:requires_documents]
        begin
          return true unless Document.where(entity: @entity).exists?
        rescue StandardError
          return true
        end
      end

      # Skip if requires collaboration but system not set up
      if test[:requires_collaboration]
        begin
          return true unless AgentEnergyState.exists?
        rescue StandardError
          return true
        end
      end

      false
    end

    def find_test_by_id(test_id)
      SystemBenchmarks.all_tests.values.flatten.find { |t| t[:id] == test_id }
    end

    # ============================================
    # REPORTING
    # ============================================

    def print_test_result(result)
      status = result[:passed] ? '✓' : '✗'
      color = result[:passed] ? "\e[32m" : "\e[31m"
      reset = "\e[0m"

      puts "  #{color}#{status}#{reset} #{result[:name]} (#{result[:execution_time_ms]}ms)"
      if result[:error]
        puts "    └─ Error: #{result[:error]}"
      elsif result[:answer]
        puts "    └─ Answer: #{result[:answer].to_s.truncate(80)}"
      end
    end

    def generate_summary(verbose: true)
      elapsed = Time.current - @start_time
      total = @results.size
      passed = @results.count { |r| r[:passed] }
      failed = total - passed

      summary = {
        started_at: @start_time,
        elapsed_seconds: elapsed.round(1),
        total_tests: total,
        passed: passed,
        failed: failed,
        pass_rate: total > 0 ? (passed.to_f / total * 100).round(1) : 0,
        avg_execution_time_ms: total > 0 ? (@results.sum { |r| r[:execution_time_ms] } / total).round : 0,
        total_tokens: @results.sum { |r| r[:tokens_used] },
        by_category: results_by_category,
        by_difficulty: results_by_difficulty,
        failed_tests: @results.select { |r| !r[:passed] }.map { |r| { id: r[:test_id], name: r[:name], error: r[:error] } }
      }

      if verbose
        puts "\n" + "=" * 60
        puts "📊 BENCHMARK SUMMARY"
        puts "=" * 60
        puts "Duration: #{elapsed.round(1)}s"
        puts "Total Tests: #{total}"
        puts "Passed: #{passed} (#{summary[:pass_rate]}%)"
        puts "Failed: #{failed}"
        puts "Avg Time: #{summary[:avg_execution_time_ms]}ms"
        puts "Total Tokens: #{summary[:total_tokens]}"
        puts ""
        puts "By Category:"
        summary[:by_category].each do |cat, stats|
          puts "  #{cat}: #{stats[:passed]}/#{stats[:total]} (#{stats[:pass_rate]}%)"
        end
        puts ""
        puts "By Difficulty:"
        summary[:by_difficulty].each do |diff, stats|
          puts "  #{diff}: #{stats[:passed]}/#{stats[:total]} (#{stats[:pass_rate]}%)"
        end

        if failed > 0
          puts ""
          puts "Failed Tests:"
          summary[:failed_tests].each do |t|
            puts "  ✗ #{t[:id]}: #{t[:name]}"
            puts "    └─ #{t[:error]}" if t[:error]
          end
        end

        puts "=" * 60
      end

      summary
    end

    def results_by_category
      @results.group_by { |r| r[:category] }.transform_values do |tests|
        passed = tests.count { |t| t[:passed] }
        {
          total: tests.size,
          passed: passed,
          pass_rate: tests.size > 0 ? (passed.to_f / tests.size * 100).round(1) : 0
        }
      end
    end

    def results_by_difficulty
      @results.group_by { |r| r[:difficulty] }.transform_values do |tests|
        passed = tests.count { |t| t[:passed] }
        {
          total: tests.size,
          passed: passed,
          pass_rate: tests.size > 0 ? (passed.to_f / tests.size * 100).round(1) : 0
        }
      end
    end

    public

    # Export results to JSON
    def export_to_json
      {
        platform: 'AMOS',
        version: Rails.application.config.try(:version) || '1.0',
        benchmark_type: 'system_wide',
        entity: @entity.name,
        timestamp: Time.current.iso8601,
        summary: generate_summary(verbose: false),
        detailed_results: @results
      }.to_json
    end

    # Export results to Markdown
    def export_to_markdown
      summary = generate_summary(verbose: false)

      md = "# AMOS System Benchmark Report\n\n"
      md += "**Generated:** #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}\n"
      md += "**Entity:** #{@entity.name}\n"
      md += "**Duration:** #{summary[:elapsed_seconds]}s\n\n"

      md += "## Summary\n\n"
      md += "| Metric | Value |\n"
      md += "|--------|-------|\n"
      md += "| Total Tests | #{summary[:total_tests]} |\n"
      md += "| Passed | #{summary[:passed]} |\n"
      md += "| Failed | #{summary[:failed]} |\n"
      md += "| Pass Rate | #{summary[:pass_rate]}% |\n"
      md += "| Avg Time | #{summary[:avg_execution_time_ms]}ms |\n"
      md += "| Total Tokens | #{summary[:total_tokens]} |\n\n"

      md += "## Results by Category\n\n"
      md += "| Category | Passed | Total | Rate |\n"
      md += "|----------|--------|-------|------|\n"
      summary[:by_category].each do |cat, stats|
        md += "| #{cat} | #{stats[:passed]} | #{stats[:total]} | #{stats[:pass_rate]}% |\n"
      end
      md += "\n"

      md += "## Results by Difficulty\n\n"
      md += "| Difficulty | Passed | Total | Rate |\n"
      md += "|------------|--------|-------|------|\n"
      summary[:by_difficulty].each do |diff, stats|
        md += "| #{diff} | #{stats[:passed]} | #{stats[:total]} | #{stats[:pass_rate]}% |\n"
      end
      md += "\n"

      if summary[:failed_tests].any?
        md += "## Failed Tests\n\n"
        summary[:failed_tests].each do |t|
          md += "- **#{t[:id]}**: #{t[:name]}\n"
          md += "  - Error: #{t[:error]}\n" if t[:error]
        end
        md += "\n"
      end

      md += "## Detailed Results\n\n"
      @results.each do |r|
        status = r[:passed] ? '✓' : '✗'
        md += "### #{status} #{r[:test_id]}: #{r[:name]}\n\n"
        md += "- **Category:** #{r[:category]}\n"
        md += "- **Difficulty:** #{r[:difficulty]}\n"
        md += "- **Time:** #{r[:execution_time_ms]}ms\n"
        md += "- **Tokens:** #{r[:tokens_used]}\n"
        md += "- **Answer:** #{r[:answer]&.truncate(100)}\n" if r[:answer]
        md += "- **Error:** #{r[:error]}\n" if r[:error]
        md += "\n"
      end

      md
    end
  end
end

