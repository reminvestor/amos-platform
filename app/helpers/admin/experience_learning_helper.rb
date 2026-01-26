# frozen_string_literal: true

module Admin
  module ExperienceLearningHelper
    def source_type_badge_class(source_type)
      case source_type
      when 'semantic_advantage'
        'bg-primary'
      when 'immediate_failure'
        'bg-danger'
      when 'reflection'
        'bg-info'
      when 'manual'
        'bg-secondary'
      when 'promoted_from_entity'
        'bg-success'
      when 'confidence_calibration'
        'bg-warning text-dark'
      when 'evolution_cycle'
        'bg-purple'
      else
        'bg-secondary'
      end
    end

    def utility_badge_class(utility_score)
      return 'bg-secondary' unless utility_score

      if utility_score >= 0.8
        'bg-success'
      elsif utility_score >= 0.6
        'bg-info'
      elsif utility_score >= 0.4
        'bg-warning text-dark'
      else
        'bg-danger'
      end
    end

    def calibration_badge_class(calibration_score)
      return 'bg-secondary' unless calibration_score

      if calibration_score >= 0.85
        'bg-success'
      elsif calibration_score >= 0.7
        'bg-info'
      elsif calibration_score >= 0.5
        'bg-warning text-dark'
      else
        'bg-danger'
      end
    end

    def success_rate_badge_class(success_rate)
      return 'bg-secondary' unless success_rate

      if success_rate >= 0.75
        'bg-success'
      elsif success_rate >= 0.5
        'bg-warning text-dark'
      else
        'bg-danger'
      end
    end

    def conflict_type_badge(conflict_type)
      case conflict_type
      when 'success_rate_divergence'
        '<span class="badge bg-danger">Success Rate Divergence</span>'.html_safe
      when 'semantic_opposition'
        '<span class="badge bg-warning text-dark">Semantic Opposition</span>'.html_safe
      else
        "<span class=\"badge bg-secondary\">#{conflict_type}</span>".html_safe
      end
    end

    def detection_method_badge(method)
      case method
      when 'keyword_match'
        '<span class="badge bg-primary">Keyword</span>'.html_safe
      when 'retry_detected'
        '<span class="badge bg-danger">Retry</span>'.html_safe
      when 'topic_change'
        '<span class="badge bg-success">Topic Change</span>'.html_safe
      else
        "<span class=\"badge bg-secondary\">#{method}</span>".html_safe
      end
    end
  end
end
