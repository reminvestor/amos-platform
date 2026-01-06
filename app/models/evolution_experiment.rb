# frozen_string_literal: true

# EvolutionExperiment - A/B tests and experiments for platform evolution
#
# Experiments compare a control (current behavior) against a variant (proposed change)
# to determine if the change actually improves performance.
#
# Experiment Types:
# - prompt_test: Compare two system prompts for an agent
# - new_tool: Test a newly created tool
# - new_capability: Test adding a capability to an agent
# - workflow_change: Test a modified workflow
#
class EvolutionExperiment < ApplicationRecord
  belongs_to :entity
  belongs_to :evolution_cycle, optional: true
  belongs_to :agent_goal, optional: true
  
  has_many :agent_plugin_executions, dependent: :nullify

  EXPERIMENT_TYPES = %w[prompt_test new_tool new_capability workflow_change configuration_change].freeze
  STATUSES = %w[pending running completed cancelled promoted].freeze

  validates :experiment_type, presence: true, inclusion: { in: EXPERIMENT_TYPES }
  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :target_executions, numericality: { greater_than: 0 }

  scope :pending, -> { where(status: 'pending') }
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :promoted, -> { where(status: 'promoted') }
  scope :by_type, ->(type) { where(experiment_type: type) }
  scope :for_target, ->(type, id) { where(target_type: type, target_id: id) }
  scope :recent, -> { order(created_at: :desc) }

  # ═══════════════════════════════════════════════════════════════════════════
  # LIFECYCLE
  # ═══════════════════════════════════════════════════════════════════════════

  def start!
    update!(
      status: 'running',
      started_at: Time.current
    )
  end

  def complete!(analysis_results = {})
    winner = determine_winner
    
    update!(
      status: 'completed',
      completed_at: Time.current,
      winner: winner,
      **analysis_results
    )
  end

  def promote!
    return unless winner == 'variant'
    
    update!(
      status: 'promoted',
      promoted_at: Time.current
    )
  end

  def cancel!(reason = nil)
    update!(
      status: 'cancelled',
      completed_at: Time.current,
      control_results: control_results.merge(cancellation_reason: reason)
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # EXECUTION TRACKING
  # ═══════════════════════════════════════════════════════════════════════════

  def record_control_execution(execution_data)
    results = control_results.dup
    results['executions'] ||= []
    results['executions'] << execution_data
    
    update!(
      control_results: results,
      control_executions: control_executions + 1
    )
    
    check_completion
  end

  def record_variant_execution(execution_data)
    results = variant_results.dup
    results['executions'] ||= []
    results['executions'] << execution_data
    
    update!(
      variant_results: results,
      variant_executions: variant_executions + 1
    )
    
    check_completion
  end

  def should_use_variant?
    return false unless running?
    
    # Alternate between control and variant for even distribution
    total = control_executions + variant_executions
    total.even?
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ANALYSIS
  # ═══════════════════════════════════════════════════════════════════════════

  def ready_for_analysis?
    control_executions >= target_executions / 2 && 
    variant_executions >= target_executions / 2
  end

  def analyze!
    return unless ready_for_analysis?
    
    control_stats = calculate_stats(control_results['executions'] || [])
    variant_stats = calculate_stats(variant_results['executions'] || [])
    
    # Calculate improvement
    improvement = if control_stats[:success_rate] > 0
                    ((variant_stats[:success_rate] - control_stats[:success_rate]) / 
                     control_stats[:success_rate] * 100).round(2)
                  else
                    variant_stats[:success_rate] > 0 ? 100.0 : 0.0
                  end
    
    # Calculate statistical significance (simplified t-test approximation)
    p_val = calculate_p_value(control_stats, variant_stats)
    significant = p_val < 0.05
    
    update!(
      improvement_percent: improvement,
      p_value: p_val,
      confidence_level: 1 - p_val,
      statistically_significant: significant
    )
  end

  def determine_winner
    return 'inconclusive' unless statistically_significant?
    
    improvement_percent.to_f > 0 ? 'variant' : 'control'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TARGET HELPERS
  # ═══════════════════════════════════════════════════════════════════════════

  def target
    return nil unless target_type.present? && target_id.present?
    target_type.constantize.find_by(id: target_id)
  end

  def target=(record)
    if record.nil?
      self.target_type = nil
      self.target_id = nil
    else
      self.target_type = record.class.name
      self.target_id = record.id
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUMMARY
  # ═══════════════════════════════════════════════════════════════════════════

  def summary
    {
      name: name,
      type: experiment_type,
      status: status,
      control_executions: control_executions,
      variant_executions: variant_executions,
      improvement_percent: improvement_percent,
      statistically_significant: statistically_significant,
      winner: winner
    }
  end

  private

  def check_completion
    total = control_executions + variant_executions
    if total >= target_executions && running?
      analyze!
      complete!
    end
  end

  def calculate_stats(executions)
    return { success_rate: 0, avg_duration: 0, count: 0 } if executions.empty?
    
    successful = executions.count { |e| e['success'] || e['status'] == 'completed' }
    durations = executions.filter_map { |e| e['duration_ms'] }
    
    {
      success_rate: (successful.to_f / executions.count * 100).round(2),
      avg_duration: durations.any? ? (durations.sum.to_f / durations.count).round : 0,
      count: executions.count
    }
  end

  def calculate_p_value(control_stats, variant_stats)
    # Simplified p-value calculation using proportions test
    # In production, you'd use a proper statistical library
    n1 = control_stats[:count]
    n2 = variant_stats[:count]
    
    return 1.0 if n1 < 10 || n2 < 10  # Not enough data
    
    p1 = control_stats[:success_rate] / 100.0
    p2 = variant_stats[:success_rate] / 100.0
    
    # Pooled proportion
    p_pool = (p1 * n1 + p2 * n2) / (n1 + n2)
    
    return 1.0 if p_pool == 0 || p_pool == 1  # Edge case
    
    # Standard error
    se = Math.sqrt(p_pool * (1 - p_pool) * (1.0/n1 + 1.0/n2))
    
    return 1.0 if se == 0  # No variance
    
    # Z-score
    z = (p2 - p1).abs / se
    
    # Convert to p-value (two-tailed)
    # Using normal approximation
    p_value = 2 * (1 - normal_cdf(z))
    p_value.round(6)
  rescue
    1.0  # Return non-significant on any error
  end

  def normal_cdf(z)
    # Approximation of the normal CDF
    # Using the error function approximation
    (1.0 + Math.erf(z / Math.sqrt(2))) / 2.0
  end
end


