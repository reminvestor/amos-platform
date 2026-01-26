# frozen_string_literal: true

module Learning
  # ConfidenceCalibrationService - Track and correct AI confidence vs actual outcomes
  #
  # Problem: AI systems often have miscalibrated confidence:
  # - Overconfident at 90% (actual success might be 70%)
  # - Underconfident at 50% (actual success might be 65%)
  #
  # This service:
  # 1. Analyzes historical confidence scores vs actual outcomes
  # 2. Generates calibration curves
  # 3. Creates adjustment factors for different confidence levels
  # 4. Generates guidance to inject into prompts
  #
  # Integration:
  # - Analyzes DecisionTrace records with confidence_score and outcome
  # - Creates CalibrationExperience that gets injected into prompts
  # - Called during evolution cycles
  #
  class ConfidenceCalibrationService
    attr_reader :entity

    # Minimum data points needed for reliable calibration
    MIN_DATA_POINTS = 20
    MIN_BUCKET_SIZE = 5

    def initialize(entity:)
      @entity = entity
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN ENTRY POINT
    # ═══════════════════════════════════════════════════════════════════════════

    def analyze_calibration(window: 30.days)
      Rails.logger.info "[ConfidenceCalibration] Analyzing calibration for entity #{entity.id}"

      # Get decision traces with both confidence and outcome
      traces = DecisionTrace.where(entity: entity)
                            .where('created_at > ?', window.ago)
                            .where.not(confidence_score: nil)
                            .where(outcome: %w[success failure])

      return insufficient_data_result if traces.count < MIN_DATA_POINTS

      # Calculate calibration metrics
      calibration = calculate_calibration(traces)
      
      # Generate guidance based on miscalibration
      guidance = generate_calibration_guidance(calibration)

      # Store as experience if significant miscalibration found
      store_calibration_experience!(guidance) if guidance[:significant_miscalibration]

      {
        data_points: traces.count,
        calibration: calibration,
        guidance: guidance,
        overall_calibration_score: calculate_overall_calibration_score(calibration)
      }
    end

    # Get calibration guidance for injection into prompts
    def get_calibration_guidance
      experience = TaskExperience.where(entity: entity, task_type: 'general')
                                 .active
                                 .where("source_type = 'confidence_calibration'")
                                 .order(created_at: :desc)
                                 .first

      return nil unless experience

      <<~GUIDANCE
        ## 📊 CONFIDENCE CALIBRATION
        
        #{experience.content}
      GUIDANCE
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # CALIBRATION CALCULATION
    # ═══════════════════════════════════════════════════════════════════════════

    def calculate_calibration(traces)
      # Bucket by confidence level (0.1 increments)
      buckets = {}

      traces.each do |trace|
        bucket = (trace.confidence_score * 10).floor / 10.0
        bucket = bucket.clamp(0.0, 0.9)  # 0.0 to 0.9 buckets

        buckets[bucket] ||= { predicted: bucket, outcomes: [] }
        buckets[bucket][:outcomes] << (trace.outcome == 'success' ? 1 : 0)
      end

      # Calculate actual success rate per bucket
      calibration = {}

      buckets.each do |bucket_key, data|
        next if data[:outcomes].count < MIN_BUCKET_SIZE

        actual_rate = data[:outcomes].sum.to_f / data[:outcomes].count
        predicted_rate = bucket_key + 0.05  # Midpoint of bucket

        calibration[bucket_key] = {
          predicted: predicted_rate,
          actual: actual_rate.round(3),
          sample_size: data[:outcomes].count,
          difference: (predicted_rate - actual_rate).round(3),
          is_overconfident: predicted_rate > actual_rate + 0.05,
          is_underconfident: predicted_rate < actual_rate - 0.05
        }
      end

      calibration
    end

    def calculate_overall_calibration_score(calibration)
      return 1.0 if calibration.empty?

      # Calculate mean absolute calibration error
      total_error = 0
      total_weight = 0

      calibration.each do |_bucket, data|
        weight = Math.log(data[:sample_size] + 1)
        total_error += data[:difference].abs * weight
        total_weight += weight
      end

      return 1.0 if total_weight.zero?

      # Convert error to score (0 error = 1.0, 0.5 error = 0.0)
      error = total_error / total_weight
      (1.0 - (error * 2)).clamp(0.0, 1.0).round(3)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # GUIDANCE GENERATION
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_calibration_guidance(calibration)
      issues = []
      significant = false

      calibration.each do |bucket, data|
        next if data[:difference].abs < 0.1  # Ignore small miscalibrations

        significant = true

        if data[:is_overconfident]
          issues << {
            type: :overconfident,
            at_confidence: data[:predicted],
            by_amount: data[:difference].abs,
            actual_rate: data[:actual],
            sample_size: data[:sample_size]
          }
        elsif data[:is_underconfident]
          issues << {
            type: :underconfident,
            at_confidence: data[:predicted],
            by_amount: data[:difference].abs,
            actual_rate: data[:actual],
            sample_size: data[:sample_size]
          }
        end
      end

      guidance_text = build_guidance_text(issues)

      {
        issues: issues,
        significant_miscalibration: significant,
        text: guidance_text
      }
    end

    def build_guidance_text(issues)
      return nil if issues.empty?

      parts = []

      # Group by type
      overconfident = issues.select { |i| i[:type] == :overconfident }
      underconfident = issues.select { |i| i[:type] == :underconfident }

      if overconfident.any?
        worst = overconfident.max_by { |i| i[:by_amount] }
        parts << "When you feel #{(worst[:at_confidence] * 100).round}%+ confident, " \
                 "your actual success rate is only #{(worst[:actual_rate] * 100).round}%. " \
                 "Consider adding verification steps or expressing more uncertainty."
      end

      if underconfident.any?
        worst = underconfident.max_by { |i| i[:by_amount] }
        parts << "When you express #{(worst[:at_confidence] * 100).round}% confidence, " \
                 "you actually succeed #{(worst[:actual_rate] * 100).round}% of the time. " \
                 "You can be more confident in similar situations."
      end

      parts.join("\n\n")
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EXPERIENCE STORAGE
    # ═══════════════════════════════════════════════════════════════════════════

    def store_calibration_experience!(guidance)
      return unless guidance[:text].present?

      # Find or create calibration experience
      existing = TaskExperience.where(entity: entity, task_type: 'general')
                               .active
                               .where("source_type = 'confidence_calibration'")
                               .first

      if existing
        existing.update!(
          content: guidance[:text],
          utility_score: 0.7,  # Calibration advice is important
          metadata: existing.metadata.merge(
            'updated_at' => Time.current.iso8601,
            'issues_count' => guidance[:issues].count
          )
        )
        Rails.logger.info "[ConfidenceCalibration] Updated calibration experience #{existing.id}"
      else
        TaskExperience.learn!(
          entity: entity,
          task_type: 'general',  # Applies to all tasks
          content: guidance[:text],
          applies_when: 'When estimating confidence or certainty',
          source_type: 'confidence_calibration',
          source_context: {
            generated_at: Time.current.iso8601,
            issues: guidance[:issues]
          }
        )
        Rails.logger.info "[ConfidenceCalibration] Created new calibration experience"
      end
    end

    def insufficient_data_result
      {
        data_points: 0,
        calibration: {},
        guidance: { issues: [], significant_miscalibration: false, text: nil },
        overall_calibration_score: nil,
        message: "Insufficient data for calibration (need #{MIN_DATA_POINTS}+ decisions with confidence scores)"
      }
    end
  end
end
