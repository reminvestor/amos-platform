module CampaignsHelper
  def campaign_status_color(status)
    case status
    when 'draft'
      'secondary'
    when 'scheduled'
      'info'
    when 'in_progress'
      'primary'
    when 'paused'
      'warning'
    when 'completed'
      'success'
    when 'stopped'
      'danger'
    else
      'secondary'
    end
  end
  
  def delivery_status_color(status)
    case status
    when 'pending'
      'secondary'
    when 'sent', 'delivered'
      'info'
    when 'opened'
      'primary'
    when 'clicked'
      'success'
    when 'failed', 'bounced'
      'danger'
    else
      'secondary'
    end
  end
end
