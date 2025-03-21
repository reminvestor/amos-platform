module ApplicationHelper
  # Return Bootstrap color class for campaign status
  def campaign_status_color(status)
    case status
    when 'draft'
      'secondary'
    when 'scheduled'
      'info'
    when 'in_progress'
      'primary'
    when 'completed'
      'success'
    when 'paused'
      'warning'
    when 'stopped'
      'danger'
    else
      'secondary'
    end
  end
  
  # Return Bootstrap color class for email delivery status
  def delivery_status_color(status)
    case status
    when 'pending'
      'secondary'
    when 'sent'
      'primary'
    when 'delivered'
      'info'
    when 'opened'
      'success'
    when 'clicked'
      'success'
    when 'bounced'
      'danger'
    when 'failed'
      'danger'
    else
      'secondary'
    end
  end
end
