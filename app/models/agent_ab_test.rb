# frozen_string_literal: true

class AgentAbTest < ApplicationRecord
  belongs_to :control_agent, class_name: 'AgentPlugin'
  belongs_to :variant_agent, class_name: 'AgentPlugin'
  belongs_to :enrollment, class_name: 'AgentSchoolEnrollment', optional: true
  belongs_to :entity

  STATUSES = %w[pending running completed cancelled].freeze
  SIGNIFICANCE_THRESHOLD = 0.05  # p-value

  # Validations
  validates :status, inclusion: { in: STATUSES }
  validates :target_tasks, numericality: { greater_than: 0 }

  # Scopes
  scope :running, -> { where(status: 'running') }
  scope :completed, -> { where(status: 'completed') }
  scope :for_agent, ->(agent) { where('control_agent_id = ? OR variant_agent_id = ?', agent.id, agent.id) }

  # ============================================
  # LIFECYCLE
  # ============================================

  def start!
    update!(
      status: 'running',
      started_at: Time.current
    )
  end

  def cancel!
    update!(
      status: 'cancelled',
      completed_at: Time.current
    )
  end

  def record_control_result!(execution)
    results = control_results.dup
    results['executions'] ||= []
    results['executions'] << extract_execution_data(execution)

    update!(
      control_results: results,
      control_tasks_completed: control_tasks_completed + 1
    )

    check_completion!
  end

  def record_variant_result!(execution)
    results = variant_results.dup
    results['executions'] ||= []
    results['executions'] << extract_execution_data(execution)

    update!(
      variant_results: results,
      variant_tasks_completed: variant_tasks_completed + 1
    )

    check_completion!
  end

  # ============================================
  # STATUS CHECKS
  # ============================================

  def running?
    status == 'running'
  end

  def completed?
    status == 'completed'
  end

  def ready_for_analysis?
    control_tasks_completed >= target_tasks && variant_tasks_completed >= target_tasks
  end

  def progress
    total_needed = target_tasks * 2
    total_completed = control_tasks_completed + variant_tasks_completed
    (total_completed.to_f / total_needed * 100).round(1)
  end

  # ============================================
  # ANALYSIS
  # ============================================

  def analyze!
    return unless ready_for_analysis?

    control_stats = calculate_stats(control_results['executions'] || [])
    variant_stats = calculate_stats(variant_results['executions'] || [])

    analysis = perform_statistical_comparison(control_stats, variant_stats)

    update!(
      status: 'completed',
      completed_at: Time.current,
      statistical_analysis: analysis,
      winner: determine_winner(analysis)
    )

    analysis
  end

  def variant_significantly_better?
    return false unless completed?
    winner == 'variant' && statistical_analysis['significant']
  end

  def no_significant_difference?
    return false unless completed?
    !statistical_analysis['significant']
  end

  private

  def check_completion!
    analyze! if ready_for_analysis? && running?
  end

  def extract_execution_data(execution)
    {
      'id' => execution.id,
      'success' => execution.status == 'completed',
      'quality' => execution.quality_score || 0.5,
      'duration_ms' => execution.duration_ms,
      'tools_used' => execution.tools_used&.size || 0,
      'created_at' => execution.created_at.iso8601
    }
  end

  def calculate_stats(executions)
    return { mean: 0.5, std: 0.1, n: 0 } if executions.empty?

    successes = executions.count { |e| e['success'] }
    qualities = executions.map { |e| e['quality'] }

    n = executions.size
    success_rate = successes.to_f / n
    mean_quality = qualities.sum / n.to_f
    std_quality = Math.sqrt(qualities.map { |q| (q - mean_quality)**2 }.sum / n)

    {
      n: n,
      success_rate: success_rate,
      mean_quality: mean_quality,
      std_quality: std_quality,
      mean_duration: executions.map { |e| e['duration_ms'] }.compact.sum / n.to_f
    }
  end

  def perform_statistical_comparison(control_stats, variant_stats)
    results = {
      metrics: {},
      significant: false,
      significant_improvements: 0,
      significant_regressions: 0
    }

    # Compare success rate
    sr_result = compare_proportions(
      control_stats[:success_rate], control_stats[:n],
      variant_stats[:success_rate], variant_stats[:n]
    )
    results[:metrics]['success_rate'] = sr_result
    if sr_result[:significant]
      if sr_result[:variant_better]
        results[:significant_improvements] += 1
      else
        results[:significant_regressions] += 1
      end
    end

    # Compare quality
    q_result = compare_means(
      control_stats[:mean_quality], control_stats[:std_quality], control_stats[:n],
      variant_stats[:mean_quality], variant_stats[:std_quality], variant_stats[:n]
    )
    results[:metrics]['quality'] = q_result
    if q_result[:significant]
      if q_result[:variant_better]
        results[:significant_improvements] += 1
      else
        results[:significant_regressions] += 1
      end
    end

    # Overall significance
    results[:significant] = results[:significant_improvements] >= 1 ||
                            results[:significant_regressions] >= 1

    results
  end

  def compare_proportions(p1, n1, p2, n2)
    return { significant: false, p_value: 1.0 } if n1 < 5 || n2 < 5

    # Two-proportion z-test
    p_pooled = (p1 * n1 + p2 * n2) / (n1 + n2)
    se = Math.sqrt(p_pooled * (1 - p_pooled) * (1.0/n1 + 1.0/n2))

    return { significant: false, p_value: 1.0 } if se == 0

    z = (p2 - p1) / se
    p_value = 2 * (1 - normal_cdf(z.abs))

    {
      control: p1,
      variant: p2,
      z_score: z,
      p_value: p_value,
      significant: p_value < SIGNIFICANCE_THRESHOLD,
      variant_better: p2 > p1
    }
  end

  def compare_means(m1, s1, n1, m2, s2, n2)
    return { significant: false, p_value: 1.0 } if n1 < 5 || n2 < 5

    # Welch's t-test
    se = Math.sqrt((s1**2 / n1) + (s2**2 / n2))
    return { significant: false, p_value: 1.0 } if se == 0

    t = (m2 - m1) / se

    # Approximate p-value using normal distribution (valid for large n)
    p_value = 2 * (1 - normal_cdf(t.abs))

    {
      control: m1,
      variant: m2,
      t_score: t,
      p_value: p_value,
      significant: p_value < SIGNIFICANCE_THRESHOLD,
      variant_better: m2 > m1
    }
  end

  def normal_cdf(x)
    # Approximation of the normal CDF
    0.5 * (1 + Math.erf(x / Math.sqrt(2)))
  end

  def determine_winner(analysis)
    if analysis[:significant_improvements] >= 1 && analysis[:significant_regressions] == 0
      'variant'
    elsif analysis[:significant_regressions] >= 1 && analysis[:significant_improvements] == 0
      'control'
    else
      'tie'
    end
  end
end

