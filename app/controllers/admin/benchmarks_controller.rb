# frozen_string_literal: true

module Admin
  class BenchmarksController < Admin::BaseController
    before_action :set_test_environment_status

    def index
      @recent_runs = BenchmarkRun.includes(:task_results)
                                 .order(created_at: :desc)
                                 .limit(20)
      
      @categories = Benchmarks::BusinessBenchmark::CATEGORIES
      @task_count = Benchmarks::BusinessBenchmark.all_tasks.count
      @difficulty_breakdown = Benchmarks::BusinessBenchmark.difficulty_breakdown
    end

    def show
      @benchmark_run = BenchmarkRun.includes(:task_results).find(params[:id])
      @task_results = @benchmark_run.task_results.order(:created_at)
    end

    # Run a new benchmark
    def create
      category = params[:category]
      run_type = params[:run_type] || 'quick'
      cleanup_before = params[:cleanup_before] == 'true'

      # Queue the benchmark job
      BenchmarkExecutionJob.perform_later(
        category: category,
        run_type: run_type,
        cleanup_before: cleanup_before,
        requested_by: current_user.id
      )

      flash[:notice] = "Benchmark started! Results will appear shortly."
      redirect_to admin_benchmarks_path
    end

    # View trends over time
    def trends
      @days = (params[:days] || 30).to_i
      
      @runs_by_day = BenchmarkRun.where('created_at > ?', @days.days.ago)
                                 .group("DATE(created_at)")
                                 .count

      @accuracy_trend = BenchmarkRun.where('created_at > ?', @days.days.ago)
                                    .group("DATE(created_at)")
                                    .average(:overall_accuracy)

      @category_performance = BenchmarkRun.where('created_at > ?', @days.days.ago)
                                          .group(:benchmark_category)
                                          .average(:overall_accuracy)
    end

    # Compare two benchmark runs
    def compare
      @run1 = BenchmarkRun.find(params[:run1_id])
      @run2 = BenchmarkRun.find(params[:run2_id])

      # Find tasks that exist in both runs
      @run1_tasks = @run1.task_results.index_by(&:task_id)
      @run2_tasks = @run2.task_results.index_by(&:task_id)
      @common_task_ids = @run1_tasks.keys & @run2_tasks.keys

      @comparison = @common_task_ids.map do |task_id|
        t1 = @run1_tasks[task_id]
        t2 = @run2_tasks[task_id]
        {
          task_id: task_id,
          run1_correct: t1.correct,
          run2_correct: t2.correct,
          run1_time: t1.execution_time_ms,
          run2_time: t2.execution_time_ms,
          improved: !t1.correct && t2.correct,
          regressed: t1.correct && !t2.correct
        }
      end

      @improvements = @comparison.count { |c| c[:improved] }
      @regressions = @comparison.count { |c| c[:regressed] }
    end

    # Clean up test environment
    def cleanup
      stats = Benchmarks::TestEnvironment.cleanup!
      flash[:notice] = "Cleanup complete: #{stats.values.sum} objects removed"
      redirect_to admin_benchmarks_path
    end

    # API endpoint to get run status
    def status
      run = BenchmarkRun.find_by(run_id: params[:run_id])
      
      if run
        render json: {
          status: run.total_tasks.present? ? 'completed' : 'running',
          total_tasks: run.total_tasks,
          correct_tasks: run.correct_tasks,
          accuracy: run.overall_accuracy,
          created_at: run.created_at
        }
      else
        render json: { status: 'not_found' }, status: :not_found
      end
    end

    private

    def set_test_environment_status
      @test_env_status = Benchmarks::TestEnvironment.status
    end
  end
end

