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

  def markdown(text)
    return '' if text.blank?
    
    # Initialize Redcarpet Markdown renderer
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      filter_html: false,
      link_attributes: { target: '_blank', rel: 'noopener noreferrer' }
    )
    
    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      lax_spacing: true,
      no_intra_emphasis: true,
      strikethrough: true,
      superscript: true,
      highlight: true,
      quote: true
    )
    
    # Process the markdown
    markdown.render(text)
  end
end
