# frozen_string_literal: true

# PlanTemplate - Reusable templates for common execution plans
#
# Templates are matched against user requests using keywords and patterns.
# They provide optimized phase/step structures based on past successes.
#
class PlanTemplate < ApplicationRecord
  STATUSES = %w[active deprecated draft].freeze
  CATEGORIES = %w[apps integrations workflows modules analytics marketing automation].freeze
  COMPLEXITIES = %w[simple medium complex epic].freeze

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :complexity, inclusion: { in: COMPLEXITIES }

  scope :active, -> { where(status: 'active') }
  scope :by_category, ->(cat) { where(category: cat) }
  scope :popular, -> { order(times_used: :desc) }
  scope :successful, -> { where('success_rate >= ?', 0.8) }

  # Find the best matching template for a request
  def self.find_best_match(request)
    request_lower = request.downcase

    active.map do |template|
      score = template.match_score(request_lower)
      [template, score] if score > 0
    end.compact
       .sort_by { |_, score| -score }
       .first
       &.first
  end

  # Calculate how well this template matches a request
  def match_score(request)
    score = 0

    # Keyword matching
    (keywords || []).each do |keyword|
      score += 10 if request.include?(keyword.downcase)
    end

    # Pattern matching
    (trigger_patterns || []).each do |pattern|
      begin
        regex = Regexp.new(pattern, Regexp::IGNORECASE)
        score += 20 if request.match?(regex)
      rescue RegexpError
        # Skip invalid patterns
      end
    end

    # Boost for high success rate
    score += 5 if success_rate && success_rate > 0.9
    score += 3 if success_rate && success_rate > 0.8

    # Boost for popularity
    score += 2 if times_used > 100
    score += 1 if times_used > 10

    score
  end

  # Create an ExecutionPlan from this template
  def create_plan(entity:, user:, request:, customizations: {})
    # Merge customizations into phases
    customized_phases = apply_customizations(phases, customizations)

    plan = ExecutionPlan.create!(
      entity: entity,
      user: user,
      title: "#{name}: #{request.truncate(50)}",
      original_request: request,
      complexity: complexity,
      status: 'planning',
      requires_approval: complexity.in?(%w[complex epic]),
      phases: customized_phases,
      total_steps: customized_phases.sum { |p| (p['steps'] || []).count },
      estimated_duration_minutes: estimated_duration_minutes,
      execution_log: [{
        timestamp: Time.current.iso8601,
        event: 'template_applied',
        message: "Created from template: #{name} (#{slug})"
      }]
    )

    # Increment usage
    increment!(:times_used)

    plan
  end

  # Record success/failure for learning
  def record_outcome(success:, duration_minutes: nil)
    if success
      increment!(:success_count)
    else
      increment!(:failure_count)
    end

    # Update success rate
    total = success_count + failure_count
    update!(success_rate: success_count.to_f / total)

    # Update average duration
    if duration_minutes && success
      current_avg = average_duration_minutes || duration_minutes
      new_avg = (current_avg * (success_count - 1) + duration_minutes) / success_count
      update!(average_duration_minutes: new_avg)
    end
  end

  private

  def apply_customizations(template_phases, customizations)
    return template_phases if customizations.empty?

    template_phases.map do |phase|
      customized_phase = phase.deep_dup

      # Apply skip_phases
      if customizations[:skip_phases]&.include?(phase['name'])
        customized_phase['skip'] = true
      end

      # Apply custom step modifications
      if customizations[:step_modifications]
        (customized_phase['steps'] || []).each do |step|
          if mod = customizations[:step_modifications][step['id']]
            step.merge!(mod.stringify_keys)
          end
        end
      end

      # Add review checkpoints if requested
      if customizations[:add_review_checkpoints]
        add_review_steps(customized_phase)
      end

      customized_phase
    end.reject { |p| p['skip'] }
  end

  def add_review_steps(phase)
    return unless phase['steps']&.any?

    # Add a review step after the last step
    last_step = phase['steps'].last
    review_step = {
      'id' => "#{last_step['id']}_review",
      'name' => "Review: #{phase['name']}",
      'description' => "User reviews the completed phase before continuing",
      'agent' => nil,
      'tools_needed' => ['ask_user'],
      'status' => 'pending',
      'dependencies' => [last_step['id']],
      'requires_input' => true,
      'estimated_minutes' => 5
    }

    phase['steps'] << review_step
  end
end





