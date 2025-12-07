# frozen_string_literal: true

# == Schema Information
#
# Table name: factory_test_sessions
#
#  id                :bigint           not null, primary key
#  entity_id         :bigint           not null
#  user_id           :bigint           not null
#  testable_type     :string           not null
#  testable_id       :bigint           not null
#  attempt_number    :integer          default(1)
#  max_attempts      :integer          default(3)
#  status            :string           default("pending")
#  total_tests       :integer          default(0)
#  passed_tests      :integer          default(0)
#  failed_tests      :integer          default(0)
#  skipped_tests     :integer          default(0)
#  overall_score     :float
#  total_duration_ms :integer
#  started_at        :datetime
#  completed_at      :datetime
#  delivered         :boolean          default(FALSE)
#  delivered_at      :datetime
#  delivery_notes    :text
#  metadata          :jsonb            default({})
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class FactoryTestSession < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================
  
  belongs_to :entity
  belongs_to :user
  belongs_to :testable, polymorphic: true
  
  has_many :factory_test_runs, dependent: :destroy

  # ============================================
  # VALIDATIONS
  # ============================================
  
  VALID_STATUSES = %w[pending running passed failed delivered].freeze
  VALID_TESTABLE_TYPES = %w[AgentPlugin ToolDefinition Integration].freeze

  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validates :testable_type, presence: true, inclusion: { in: VALID_TESTABLE_TYPES }
  validates :attempt_number, numericality: { greater_than: 0 }
  validates :max_attempts, numericality: { greater_than: 0, less_than_or_equal_to: 10 }

  # ============================================
  # SCOPES
  # ============================================
  
  scope :pending, -> { where(status: 'pending') }
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: %w[passed failed delivered]) }
  scope :for_testable, ->(testable) { where(testable: testable) }
  scope :recent, -> { order(created_at: :desc) }
  scope :delivered, -> { where(delivered: true) }

  # ============================================
  # CALLBACKS
  # ============================================
  
  after_save :update_stats, if: :saved_change_to_status?

  # ============================================
  # STATE MACHINE
  # ============================================
  
  def start!
    update!(status: 'running', started_at: Time.current)
  end

  def complete!
    recalculate_stats!
    new_status = all_required_passed? ? 'passed' : 'failed'
    update!(
      status: new_status,
      completed_at: Time.current,
      total_duration_ms: started_at ? ((Time.current - started_at) * 1000).to_i : nil
    )
  end

  def deliver!(notes: nil)
    update!(
      status: 'delivered',
      delivered: true,
      delivered_at: Time.current,
      delivery_notes: notes
    )
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================
  
  def completed?
    status.in?(%w[passed failed delivered])
  end

  def success?
    status == 'passed' || (status == 'delivered' && overall_score.to_f >= 0.7)
  end

  def can_retry?
    !completed? || (status == 'failed' && attempt_number < max_attempts)
  end

  def attempts_remaining
    [max_attempts - attempt_number, 0].max
  end

  def all_required_passed?
    criteria = FactoryTestCriteria.for_testable(testable).active.required
    return true if criteria.empty?
    
    criteria_ids = criteria.pluck(:id)
    passing_ids = factory_test_runs.passed.where(factory_test_criteria_id: criteria_ids).pluck(:factory_test_criteria_id).uniq
    
    (criteria_ids - passing_ids).empty?
  end

  def recalculate_stats!
    runs = factory_test_runs.completed
    
    self.total_tests = runs.count
    self.passed_tests = runs.passed.count
    self.failed_tests = runs.failed.count
    self.skipped_tests = runs.where(status: %w[skipped error]).count
    
    # Calculate weighted score
    if total_tests > 0
      total_possible = runs.sum { |r| r.factory_test_criteria.max_score }
      total_achieved = runs.passed.sum { |r| r.factory_test_criteria.max_score }
      self.overall_score = total_possible > 0 ? (total_achieved.to_f / total_possible) : 0.0
    else
      self.overall_score = 0.0
    end
    
    save! if changed?
  end

  # Get summary for display
  def summary
    emoji = case status
            when 'passed' then '✅'
            when 'failed' then '❌'
            when 'delivered' then '📦'
            when 'running' then '🔄'
            else '⏳'
            end
    
    "#{emoji} Attempt #{attempt_number}/#{max_attempts}: #{passed_tests}/#{total_tests} tests passed (#{(overall_score.to_f * 100).round}%)"
  end

  # Get detailed report for user
  def detailed_report
    {
      summary: summary,
      status: status,
      attempt: attempt_number,
      max_attempts: max_attempts,
      score: overall_score,
      tests: {
        total: total_tests,
        passed: passed_tests,
        failed: failed_tests,
        skipped: skipped_tests
      },
      can_retry: can_retry?,
      attempts_remaining: attempts_remaining,
      duration_ms: total_duration_ms,
      runs: factory_test_runs.includes(:factory_test_criteria).order(:created_at).map do |run|
        {
          name: run.criteria_name,
          status: run.status,
          passed: run.passed,
          required: run.criteria_is_required,
          score: run.similarity_score,
          error: run.error_message,
          feedback: run.ai_feedback,
          fix_suggestion: run.fix_suggestion
        }
      end
    }
  end

  # Create next attempt session
  def create_retry_session!
    return nil unless can_retry?
    
    FactoryTestSession.create!(
      entity: entity,
      user: user,
      testable: testable,
      attempt_number: attempt_number + 1,
      max_attempts: max_attempts,
      metadata: metadata.merge(previous_session_id: id)
    )
  end

  private

  def update_stats
    recalculate_stats! if completed?
  end
end

