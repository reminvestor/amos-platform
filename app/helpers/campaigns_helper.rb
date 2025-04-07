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
  
  def drip_condition_color(condition)
    case condition
    when 'not_opened'
      'warning'
    when 'not_clicked'
      'info'
    when 'opened'
      'primary'
    when 'clicked'
      'success'
    when 'always'
      'secondary'
    else
      'secondary'
    end
  end
  
  def drip_condition_description(condition)
    case condition
    when 'not_opened'
      'Contacts who did not open the original email'
    when 'not_clicked'
      'Contacts who did not click any links in the original email'
    when 'opened'
      'Contacts who opened but did not click in the original email'
    when 'clicked'
      'Contacts who clicked links in the original email'
    when 'always'
      'All contacts from the original campaign'
    else
      'Unknown condition'
    end
  end
end
