# frozen_string_literal: true

module Collaboration
  class BenchmarkRunner
    # Benchmark tasks with verifiable answers
    BENCHMARK_TASKS = [
      {
        id: 'math_simple',
        task: 'What is 15 * 7?',
        expected_answer: '105',
        category: 'math',
        difficulty: 'easy',
        specialist: nil  # Any agent should handle this
      },
      {
        id: 'math_complex',
        task: 'Calculate the compound interest on $1000 at 5% annual rate for 3 years, compounded annually. Give the final amount.',
        expected_answer: '1157.63',  # 1000 * (1.05)^3
        category: 'math',
        difficulty: 'medium',
        specialist: nil
      },
      {
        id: 'geography',
        task: 'What is the capital city of Australia?',
        expected_answer: 'Canberra',
        category: 'knowledge',
        difficulty: 'easy',
        specialist: 'web_research_specialist'
      },
      {
        id: 'weather_current',
        task: 'Is it currently daytime or nighttime in Tokyo, Japan?',
        expected_answer: :dynamic,  # We'll calculate based on actual time
        category: 'weather',
        difficulty: 'medium',
        specialist: 'weather_scout'
      },
      {
        id: 'analysis_simple',
        task: 'Given the numbers [10, 20, 30, 40, 50], what is the average?',
        expected_answer: '30',
        category: 'analysis',
        difficulty: 'easy',
        specialist: nil
      },
      {
        id: 'content_quality',
        task: 'Rate this sentence for grammar (good/bad): "The quick brown fox jumps over the lazy dog."',
        expected_answer: 'good',
        category: 'content',
        difficulty: 'easy',
        specialist: 'content_quality_analyzer'
      }
    ].freeze

    attr_reader :results, :entity, :user

    def initialize(entity:, user:)
      @entity = entity
      @user = user
      @results = []
    end

    # ============================================
    # MAIN BENCHMARK METHODS
    # ============================================

    # Run a single task on a specific agent and measure real results
    def run_single_benchmark(agent_slug:, task_id:, allow_collaboration: true, custom_question: nil)
      agent = AgentPlugin.find_by(slug: agent_slug, entity: @entity)
      return { error: "Agent '#{agent_slug}' not found" } unless agent

      # If custom_question is provided, create an ad-hoc task
      if custom_question
        task = {
          id: task_id,
          task: custom_question,
          expected_answer: nil,  # Will be validated externally
          category: 'custom',
          difficulty: 'unknown',
          specialist: nil
        }
        return run_task_on_agent(agent, task, allow_collaboration: allow_collaboration)
      end

      # Check internal benchmarks first
      task = BENCHMARK_TASKS.find { |t| t[:id] == task_id }
      
      # Check public benchmarks if not found
      unless task
        public_benchmark = PublicBenchmarks.all_benchmarks.values.flatten.find { |b| b[:id] == task_id }
        if public_benchmark
          task = {
            id: public_benchmark[:id],
            task: public_benchmark[:question],
            expected_answer: public_benchmark[:answer],
            category: task_id.split('_').first,
            difficulty: public_benchmark[:difficulty],
            specialist: nil
          }
        end
      end
      
      return { error: "Task '#{task_id}' not found" } unless task

      run_task_on_agent(agent, task, allow_collaboration: allow_collaboration)
    end

    # Run all benchmark tasks on a specific agent
    def run_agent_benchmark(agent_slug:, allow_collaboration: true)
      agent = AgentPlugin.find_by(slug: agent_slug, entity: @entity)
      return { error: "Agent '#{agent_slug}' not found" } unless agent

      results = BENCHMARK_TASKS.map do |task|
        Rails.logger.info "[Benchmark] Running task '#{task[:id]}' on agent '#{agent_slug}'"
        run_task_on_agent(agent, task, allow_collaboration: allow_collaboration)
      end

      summarize_results(agent_slug, results, allow_collaboration)
    end

    # A/B test: Run same tasks with collaboration ON vs OFF
    def run_ab_comparison(agent_slug:)
      agent = AgentPlugin.find_by(slug: agent_slug, entity: @entity)
      return { error: "Agent '#{agent_slug}' not found" } unless agent

      Rails.logger.info "[Benchmark] Starting A/B comparison for agent '#{agent_slug}'"

      # Run with collaboration disabled
      Rails.logger.info "[Benchmark] Phase 1: Collaboration DISABLED"
      results_without = BENCHMARK_TASKS.map do |task|
        run_task_on_agent(agent, task, allow_collaboration: false)
      end

      # Reset agent energy between tests
      agent.energy_state&.update!(current_energy: 75.0)

      # Run with collaboration enabled
      Rails.logger.info "[Benchmark] Phase 2: Collaboration ENABLED"
      results_with = BENCHMARK_TASKS.map do |task|
        run_task_on_agent(agent, task, allow_collaboration: true)
      end

      {
        agent: agent_slug,
        without_collaboration: summarize_results(agent_slug, results_without, false),
        with_collaboration: summarize_results(agent_slug, results_with, true),
        comparison: compare_results(results_without, results_with)
      }
    end

    # Cross-domain test: Give specialist tasks to non-specialists
    def run_cross_domain_test
      results = []

      BENCHMARK_TASKS.select { |t| t[:specialist].present? }.each do |task|
        specialist = AgentPlugin.find_by(slug: task[:specialist], entity: @entity)
        
        # Find a non-specialist agent
        non_specialist = AgentPlugin.active
          .where(entity: @entity)
          .where.not(slug: task[:specialist])
          .where.not(slug: 'scout')  # Don't use the main orchestrator
          .first

        next unless specialist && non_specialist

        Rails.logger.info "[Benchmark] Cross-domain: '#{task[:id]}' - Specialist: #{specialist.slug}, Non-specialist: #{non_specialist.slug}"

        # Run on specialist (should succeed)
        specialist_result = run_task_on_agent(specialist, task, allow_collaboration: false)

        # Run on non-specialist WITHOUT collaboration (likely to struggle)
        non_specialist_solo = run_task_on_agent(non_specialist, task, allow_collaboration: false)

        # Run on non-specialist WITH collaboration (should ask specialist for help)
        non_specialist.energy_state&.update!(current_energy: 75.0)
        non_specialist_collab = run_task_on_agent(non_specialist, task, allow_collaboration: true)

        results << {
          task_id: task[:id],
          category: task[:category],
          specialist: {
            agent: specialist.slug,
            correct: specialist_result[:correct],
            execution_time_ms: specialist_result[:execution_time_ms]
          },
          non_specialist_solo: {
            agent: non_specialist.slug,
            correct: non_specialist_solo[:correct],
            execution_time_ms: non_specialist_solo[:execution_time_ms]
          },
          non_specialist_with_help: {
            agent: non_specialist.slug,
            correct: non_specialist_collab[:correct],
            asked_for_help: non_specialist_collab[:asked_for_help],
            helper_used: non_specialist_collab[:helper_used],
            execution_time_ms: non_specialist_collab[:execution_time_ms]
          },
          collaboration_helped: non_specialist_collab[:correct] && !non_specialist_solo[:correct]
        }
      end

      {
        tests: results,
        summary: {
          total_tests: results.size,
          collaboration_helped_count: results.count { |r| r[:collaboration_helped] },
          specialist_success_rate: calculate_rate(results, ->(r) { r[:specialist][:correct] }),
          non_specialist_solo_success_rate: calculate_rate(results, ->(r) { r[:non_specialist_solo][:correct] }),
          non_specialist_collab_success_rate: calculate_rate(results, ->(r) { r[:non_specialist_with_help][:correct] })
        }
      }
    end

    private

    # ============================================
    # TASK EXECUTION
    # ============================================

    def run_task_on_agent(agent, task, allow_collaboration:)
      start_time = Time.current
      
      # Create execution record (entity is derived from agent_plugin association)
      execution = AgentPluginExecution.create!(
        agent_plugin: agent,
        user: @user,
        status: 'running',
        input_context: {
          'task_description' => task[:task],
          'benchmark_task_id' => task[:id],
          'allow_collaboration' => allow_collaboration
        },
        started_at: start_time
      )

      begin
        # Track initial state
        initial_energy = agent.current_energy
        initial_collab_count = agent.collaboration_requests_made.count

        # Actually run the agent
        result = execute_agent_task(agent, execution, task[:task], allow_collaboration)

        # Check for collaboration
        new_collab_count = agent.reload.collaboration_requests_made.count
        asked_for_help = new_collab_count > initial_collab_count
        
        helper_used = nil
        if asked_for_help
          latest_request = agent.collaboration_requests_made.order(created_at: :desc).first
          helper_used = latest_request&.helper_agent&.slug
        end

        # Verify answer
        correct = verify_answer(result, task)

        end_time = Time.current
        execution_time_ms = ((end_time - start_time) * 1000).round

        # Update execution record
        execution.update!(
          status: 'completed',
          output_result: {
            'answer' => result,
            'correct' => correct,
            'expected' => task[:expected_answer],
            'asked_for_help' => asked_for_help,
            'helper_used' => helper_used
          },
          completed_at: end_time,
          duration_ms: execution_time_ms
        )

        {
          task_id: task[:id],
          agent: agent.slug,
          success: true,
          correct: correct,
          answer: result&.to_s&.truncate(200),
          expected: task[:expected_answer].to_s,
          asked_for_help: asked_for_help,
          helper_used: helper_used,
          execution_time_ms: execution_time_ms,
          energy_before: initial_energy,
          energy_after: agent.reload.current_energy,
          allow_collaboration: allow_collaboration
        }

      rescue => e
        Rails.logger.error "[Benchmark] Task failed: #{e.message}"
        execution.update!(status: 'failed', output_result: { 'error' => e.message })

        {
          task_id: task[:id],
          agent: agent.slug,
          success: false,
          correct: false,
          error: e.message,
          asked_for_help: false,
          helper_used: nil,
          execution_time_ms: ((Time.current - start_time) * 1000).round,
          allow_collaboration: allow_collaboration
        }
      end
    end

    def execute_agent_task(agent, execution, task_description, allow_collaboration)
      # Build context
      context = {
        entity: @entity,
        user: @user,
        execution: execution,
        allow_collaboration: allow_collaboration
      }

      # Instantiate and run the agent
      agent_instance = agent.instantiate(
        entity: @entity,
        user: @user,
        execution: execution
      )

      # Run the task
      result = agent_instance.run(task_description, context)

      # Extract the answer from the result
      extract_answer(result)
    end

    def extract_answer(result)
      return result if result.is_a?(String)
      return result['answer'] if result.is_a?(Hash) && result['answer']
      return result[:answer] if result.is_a?(Hash) && result[:answer]
      return result['result'] if result.is_a?(Hash) && result['result']
      return result[:result] if result.is_a?(Hash) && result[:result]
      return result['summary'] if result.is_a?(Hash) && result['summary']
      result.to_s
    end

    def verify_answer(result, task)
      return false if result.nil?

      expected = task[:expected_answer]
      
      # Handle dynamic expected answers
      if expected == :dynamic || expected == :multi_task
        return verify_dynamic_answer(result, task)
      end

      # Try using PublicBenchmarks validator if this is a public benchmark
      public_benchmark = PublicBenchmarks.all_benchmarks.values.flatten.find { |b| b[:id] == task[:id] }
      if public_benchmark
        return PublicBenchmarks.validate_answer(public_benchmark, result)
      end

      result_str = result.to_s.downcase.strip
      expected_str = expected.to_s.downcase.strip

      # Check for exact match
      return true if result_str.include?(expected_str)

      # Check for numeric match (with some tolerance)
      if numeric?(expected_str)
        result_num = extract_number(result_str)
        expected_num = expected_str.to_f
        return (result_num - expected_num).abs < 0.1 if result_num
      end

      false
    end

    def verify_dynamic_answer(result, task)
      case task[:id]
      when 'weather_current'
        # Check if Tokyo time is day or night
        tokyo_time = Time.current.in_time_zone('Asia/Tokyo')
        expected = tokyo_time.hour.between?(6, 18) ? 'day' : 'night'
        result.to_s.downcase.include?(expected)
      else
        false
      end
    end

    def numeric?(str)
      Float(str) rescue false
    end

    def extract_number(str)
      match = str.match(/[\d,]+\.?\d*/)
      return nil unless match
      match[0].gsub(',', '').to_f
    end

    # ============================================
    # RESULT ANALYSIS
    # ============================================

    def summarize_results(agent_slug, results, allow_collaboration)
      successful = results.select { |r| r[:success] }
      correct = results.select { |r| r[:correct] }
      asked_for_help = results.select { |r| r[:asked_for_help] }

      {
        agent: agent_slug,
        allow_collaboration: allow_collaboration,
        total_tasks: results.size,
        successful_executions: successful.size,
        correct_answers: correct.size,
        accuracy: results.size > 0 ? (correct.size.to_f / results.size * 100).round(1) : 0,
        asked_for_help_count: asked_for_help.size,
        avg_execution_time_ms: successful.any? ? (successful.sum { |r| r[:execution_time_ms] } / successful.size).round : 0,
        results: results
      }
    end

    def compare_results(without_collab, with_collab)
      without_correct = without_collab.count { |r| r[:correct] }
      with_correct = with_collab.count { |r| r[:correct] }

      without_rate = without_collab.size > 0 ? (without_correct.to_f / without_collab.size * 100) : 0
      with_rate = with_collab.size > 0 ? (with_correct.to_f / with_collab.size * 100) : 0

      improvement = with_rate - without_rate

      {
        without_collaboration_accuracy: without_rate.round(1),
        with_collaboration_accuracy: with_rate.round(1),
        improvement_percentage_points: improvement.round(1),
        collaboration_helped: improvement > 0,
        tasks_where_collab_helped: with_collab.each_with_index.count do |r, i|
          r[:correct] && !without_collab[i][:correct]
        end,
        tasks_where_collab_hurt: with_collab.each_with_index.count do |r, i|
          !r[:correct] && without_collab[i][:correct]
        end
      }
    end

    def calculate_rate(results, accessor)
      return 0 if results.empty?
      (results.count { |r| accessor.call(r) }.to_f / results.size * 100).round(1)
    end
  end
end

