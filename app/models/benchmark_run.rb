# frozen_string_literal: true

class BenchmarkRun < ApplicationRecord
  belongs_to :entity
  has_many :task_results, class_name: 'BenchmarkTaskResult', dependent: :destroy

  # Run types
  RUN_TYPES = %w[single category full ab_comparison cross_domain v2_benchmark].freeze
  
  # Categories
  CATEGORIES = %w[gsm8k hotpot tool_use collaboration mixed].freeze

  validates :run_id, presence: true, uniqueness: true
  validates :run_type, presence: true, inclusion: { in: RUN_TYPES }

  scope :recent, ->(limit = 10) { order(created_at: :desc).limit(limit) }
  scope :for_category, ->(cat) { where(benchmark_category: cat) }
  scope :completed, -> { where.not(completed_at: nil) }
  scope :with_collaboration, -> { where(collaboration_enabled: true) }
  scope :without_collaboration, -> { where(collaboration_enabled: false) }

  before_validation :set_run_id, on: :create
  before_validation :set_environment, on: :create

  def duration_seconds
    return nil unless started_at && completed_at
    (completed_at - started_at).round(1)
  end

  def success_rate
    return 0 if total_tasks.zero?
    (correct_count.to_f / total_tasks * 100).round(1)
  end

  def collaboration_rate
    return 0 if total_tasks.zero?
    (collaboration_requests.to_f / total_tasks * 100).round(1)
  end

  def collaboration_effectiveness
    return 0 if collaboration_requests.zero?
    (collaboration_helped_count.to_f / collaboration_requests * 100).round(1)
  end

  def complete!(summary = {})
    update!(
      completed_at: Time.current,
      total_tasks: summary[:total_tasks] || task_results.count,
      correct_count: summary[:correct_count] || task_results.where(correct: true).count,
      failed_count: summary[:failed_count] || task_results.where(correct: false).count,
      accuracy_percentage: summary[:accuracy_percentage],
      avg_execution_time_ms: summary[:avg_execution_time_ms],
      total_tokens_used: summary[:total_tokens_used] || 0,
      total_cost_cents: summary[:total_cost_cents] || 0.0,
      collaboration_requests: summary[:collaboration_requests] || task_results.where(asked_for_help: true).count,
      collaboration_helped_count: summary[:collaboration_helped_count] || task_results.where(collaboration_helped: true).count
    )
  end

  def to_report
    {
      run_id: run_id,
      run_type: run_type,
      category: benchmark_category,
      agent: agent_slug,
      collaboration_enabled: collaboration_enabled,
      environment: environment,
      model: model_used,
      git_commit: git_commit,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      duration_seconds: duration_seconds,
      metrics: {
        total_tasks: total_tasks,
        correct: correct_count,
        failed: failed_count,
        accuracy: accuracy_percentage,
        avg_time_ms: avg_execution_time_ms,
        tokens_used: total_tokens_used,
        cost_cents: total_cost_cents
      },
      collaboration: {
        requests: collaboration_requests,
        helped: collaboration_helped_count,
        rate: collaboration_rate,
        effectiveness: collaboration_effectiveness
      },
      task_results: task_results.map(&:to_report)
    }
  end

  private

  def set_run_id
    self.run_id ||= SecureRandom.uuid
  end

  def set_environment
    self.environment ||= Rails.env
  end
end

