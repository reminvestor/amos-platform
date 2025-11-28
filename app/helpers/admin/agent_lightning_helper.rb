# frozen_string_literal: true

module Admin
  module AgentLightningHelper
    def job_status_badge_class(status)
      case status
      when 'running'
        'bg-warning text-dark'
      when 'completed'
        'bg-success'
      when 'failed'
        'bg-danger'
      when 'pending'
        'bg-secondary'
      else
        'bg-secondary'
      end
    end

    def optimization_status_badge_class(status)
      case status
      when 'applied'
        'bg-success'
      when 'rolled_back'
        'bg-warning text-dark'
      when 'failed'
        'bg-danger'
      when 'pending'
        'bg-secondary'
      else
        'bg-secondary'
      end
    end

    def trace_status_badge_class(status)
      case status
      when 'completed'
        'bg-success'
      when 'running'
        'bg-warning text-dark'
      when 'failed'
        'bg-danger'
      when 'pending'
        'bg-secondary'
      else
        'bg-secondary'
      end
    end

    def improvement_color_class(percentage)
      if percentage > 10
        'text-success'
      elsif percentage > 0
        'text-info'
      elsif percentage < -10
        'text-danger'
      elsif percentage < 0
        'text-warning'
      else
        'text-muted'
      end
    end
  end
end

