# frozen_string_literal: true

class AgentDecisionBoundary < ApplicationRecord
  belongs_to :agent_plugin

  # Validations
  validates :agent_plugin_id, uniqueness: true

  # ============================================
  # DECISION MAKING
  # ============================================

  def should_ask_for_help?(confidence)
    # Thompson Sampling: Sample from posterior to balance explore/exploit
    sampled_threshold = sample_threshold

    decision = confidence < sampled_threshold

    # Record pending decision (will be updated when outcome is known)
    record_decision(confidence, decision)

    {
      should_ask: decision,
      confidence: confidence,
      sampled_threshold: sampled_threshold,
      reasoning: generate_reasoning(confidence, sampled_threshold)
    }
  end

  # ============================================
  # LEARNING
  # ============================================

  def learn_from_outcome!(confidence:, asked_for_help:, success:, quality:)
    if asked_for_help
      if success && quality > 0.7
        # Asking was a good choice
        self.ask_alpha += 1
      else
        # Asked but still poor result
        self.ask_beta += 0.5
      end
    else
      if success && quality > 0.7
        # Solo worked well
        self.solo_alpha += 1
      else
        # Solo failed - should have asked
        self.solo_beta += 2  # Strong signal
        self.ask_alpha += 1  # Increase asking tendency
      end
    end

    # Update total decisions
    self.total_decisions += 1
    self.correct_decisions += 1 if decision_was_correct?(asked_for_help, success, quality)

    # Update current threshold
    self.current_threshold = calculate_optimal_threshold

    # Trim decision history to last 100
    if decision_history.size > 100
      self.decision_history = decision_history.last(100)
    end

    save!
  end

  def update_from_recent_outcomes
    # Called hourly to recalculate based on recent performance
    recent = decision_history.last(20)
    return if recent.empty?

    correct = recent.count { |d| d['correct'] }
    accuracy = correct.to_f / recent.size

    # If accuracy is low, shift toward asking more
    if accuracy < 0.5
      self.ask_alpha += 0.5
      self.solo_beta += 0.5
    end

    self.current_threshold = calculate_optimal_threshold
    save!
  end

  # ============================================
  # STATISTICS
  # ============================================

  def accuracy
    return 0.5 if total_decisions.zero?
    correct_decisions.to_f / total_decisions
  end

  def ask_tendency
    # How likely to recommend asking (0-1)
    ask_alpha / (ask_alpha + ask_beta)
  end

  def solo_tendency
    # How likely solo works (0-1)
    solo_alpha / (solo_alpha + solo_beta)
  end

  private

  def sample_threshold
    # Beta distribution sampling for Thompson Sampling
    ask_sample = beta_sample(ask_alpha, ask_beta)
    solo_sample = beta_sample(solo_alpha, solo_beta)

    # Convert to threshold
    if ask_sample > solo_sample
      # Asking has been working - lower threshold to ask more often
      threshold = 100 - (ask_sample * 50)  # 50-100 range
    else
      # Solo has been working - higher threshold to ask less
      threshold = 50 + (solo_sample * 30)  # 50-80 range
    end

    # Add exploration noise
    threshold + rand(-5.0..5.0)
  end

  def beta_sample(alpha, beta)
    # Simple beta distribution sampling using gamma
    x = gamma_sample(alpha)
    y = gamma_sample(beta)
    x / (x + y)
  end

  def gamma_sample(shape)
    # Marsaglia and Tsang's method for gamma sampling
    return -Math.log(rand) if shape < 1

    d = shape - 1.0 / 3.0
    c = 1.0 / Math.sqrt(9.0 * d)

    loop do
      x = gaussian_sample
      v = (1.0 + c * x)**3

      next if v <= 0

      u = rand
      if u < 1.0 - 0.0331 * (x**2)**2 ||
         Math.log(u) < 0.5 * x**2 + d * (1.0 - v + Math.log(v))
        return d * v
      end
    end
  end

  def gaussian_sample
    # Box-Muller transform
    u1 = rand
    u2 = rand
    Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2)
  end

  def record_decision(confidence, decision)
    self.decision_history << {
      confidence: confidence,
      asked: decision,
      timestamp: Time.current.iso8601,
      correct: nil  # Will be updated when outcome is known
    }
  end

  def decision_was_correct?(asked_for_help, success, quality)
    if asked_for_help
      # Correct if it led to success or quality > 0.7
      success || quality > 0.7
    else
      # Correct if solo succeeded with good quality
      success && quality > 0.6
    end
  end

  def calculate_optimal_threshold
    # Based on current beliefs, what's the optimal threshold?
    ask_expected = ask_alpha / (ask_alpha + ask_beta)
    solo_expected = solo_alpha / (solo_alpha + solo_beta)

    if ask_expected > solo_expected
      # Asking works better - lower threshold
      60 - (ask_expected - solo_expected) * 30
    else
      # Solo works better - higher threshold
      60 + (solo_expected - ask_expected) * 20
    end.clamp(30, 80)
  end

  def generate_reasoning(confidence, threshold)
    if confidence >= threshold
      "Confidence (#{confidence.round}%) exceeds threshold (#{threshold.round}%) - proceeding solo"
    else
      "Confidence (#{confidence.round}%) below threshold (#{threshold.round}%) - should ask for help"
    end
  end
end

