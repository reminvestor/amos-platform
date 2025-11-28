# frozen_string_literal: true

module Api
  module V1
    class BenchmarksController < Api::BaseController
      before_action :authenticate_user!
      before_action :set_entity

      # GET /api/v1/benchmarks
      # Returns recent benchmark runs
      def index
        runs = BenchmarkRun.where(entity: @entity)
          .completed
          .order(created_at: :desc)
          .limit(params[:limit] || 20)

        render json: {
          success: true,
          runs: runs.map { |r| run_summary(r) },
          total: BenchmarkRun.where(entity: @entity).completed.count
        }
      end

      # GET /api/v1/benchmarks/:id
      # Returns detailed benchmark run with task results
      def show
        run = BenchmarkRun.find_by!(run_id: params[:id], entity: @entity)
        render json: {
          success: true,
          run: run.to_report
        }
      end

      # GET /api/v1/benchmarks/report
      # Generate comprehensive report
      def report
        days = (params[:days] || 30).to_i
        format = params[:format] || 'json'

        case format
        when 'markdown'
          markdown = Collaboration::BenchmarkTracker.export_to_markdown(entity: @entity, days: days)
          render plain: markdown, content_type: 'text/markdown'
        else
          json = Collaboration::BenchmarkTracker.export_to_json(entity: @entity, days: days)
          render json: json
        end
      end

      # GET /api/v1/benchmarks/trends
      # Get trend data for charts
      def trends
        days = (params[:days] || 30).to_i
        runs = BenchmarkRun.where(entity: @entity)
          .completed
          .where('created_at > ?', days.days.ago)
          .order(created_at: :asc)

        # Group by day
        daily_data = runs.group_by { |r| r.created_at.to_date }.map do |date, day_runs|
          {
            date: date.iso8601,
            runs: day_runs.count,
            accuracy: Collaboration::BenchmarkTracker.send(:weighted_accuracy, day_runs),
            collaboration_rate: calculate_collab_rate(day_runs),
            tasks: day_runs.sum(&:total_tasks)
          }
        end

        render json: {
          success: true,
          period_days: days,
          data: daily_data,
          summary: {
            total_runs: runs.count,
            avg_accuracy: Collaboration::BenchmarkTracker.send(:weighted_accuracy, runs),
            trend: calculate_trend(daily_data.map { |d| d[:accuracy] })
          }
        }
      end

      # GET /api/v1/benchmarks/comparison
      # Compare collaboration ON vs OFF
      def comparison
        days = (params[:days] || 30).to_i
        
        with_collab = BenchmarkRun.where(entity: @entity)
          .completed
          .with_collaboration
          .where('created_at > ?', days.days.ago)

        without_collab = BenchmarkRun.where(entity: @entity)
          .completed
          .without_collaboration
          .where('created_at > ?', days.days.ago)

        render json: {
          success: true,
          period_days: days,
          with_collaboration: {
            runs: with_collab.count,
            accuracy: Collaboration::BenchmarkTracker.send(:weighted_accuracy, with_collab),
            avg_collab_rate: calculate_collab_rate(with_collab)
          },
          without_collaboration: {
            runs: without_collab.count,
            accuracy: Collaboration::BenchmarkTracker.send(:weighted_accuracy, without_collab)
          },
          improvement: calculate_improvement(with_collab, without_collab)
        }
      end

      # POST /api/v1/benchmarks/run
      # Trigger a benchmark run
      def run
        category = params[:category] || 'mixed'
        agent_slug = params[:agent_slug]
        
        # Queue the benchmark job
        ScheduledBenchmarkJob.perform_later(
          @entity.id,
          { category: category, agent_slug: agent_slug }
        )

        render json: {
          success: true,
          message: "Benchmark run queued for category: #{category}"
        }
      end

      private

      def set_entity
        @entity = current_user.entity
      end

      def run_summary(run)
        {
          run_id: run.run_id,
          type: run.run_type,
          category: run.benchmark_category,
          agent: run.agent_slug,
          collaboration_enabled: run.collaboration_enabled,
          accuracy: run.accuracy_percentage,
          tasks: run.total_tasks,
          correct: run.correct_count,
          collaboration_rate: run.collaboration_rate,
          created_at: run.created_at.iso8601,
          duration_seconds: run.duration_seconds
        }
      end

      def calculate_collab_rate(runs)
        return 0 if runs.empty?
        total_tasks = runs.sum(&:total_tasks)
        return 0 if total_tasks.zero?
        (runs.sum(&:collaboration_requests).to_f / total_tasks * 100).round(1)
      end

      def calculate_trend(values)
        return 'stable' if values.size < 2
        
        recent = values.last(3).sum / [values.last(3).size, 1].max
        older = values.first(3).sum / [values.first(3).size, 1].max
        
        diff = recent - older
        
        if diff > 5
          'improving'
        elsif diff < -5
          'declining'
        else
          'stable'
        end
      end

      def calculate_improvement(with_collab, without_collab)
        with_acc = Collaboration::BenchmarkTracker.send(:weighted_accuracy, with_collab)
        without_acc = Collaboration::BenchmarkTracker.send(:weighted_accuracy, without_collab)
        
        {
          percentage_points: (with_acc - without_acc).round(1),
          relative: without_acc > 0 ? ((with_acc - without_acc) / without_acc * 100).round(1) : 0
        }
      end
    end
  end
end

