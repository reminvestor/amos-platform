module ApplicationHelper
  # Return Bootstrap color class for campaign status
  def campaign_status_color(status)
    case status
    when "draft"
      "secondary"
    when "scheduled"
      "info"
    when "in_progress"
      "primary"
    when "completed"
      "success"
    when "paused"
      "warning"
    when "stopped"
      "danger"
    else
      "secondary"
    end
  end

  # Return Bootstrap color class for email delivery status
  def delivery_status_color(status)
    case status
    when "pending"
      "secondary"
    when "sent"
      "primary"
    when "delivered"
      "info"
    when "opened"
      "success"
    when "clicked"
      "success"
    when "bounced"
      "danger"
    when "failed"
      "danger"
    else
      "secondary"
    end
  end

  def markdown(text)
    return "" if text.blank?

    # Initialize Redcarpet Markdown renderer
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      filter_html: false,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
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

  # Generate a consistent color for an avatar based on a seed string (like email)
  def generate_avatar_color(seed)
    # Generate a consistent color based on the seed (email)
    hash = 0
    seed.to_s.each_byte do |b|
      hash = hash * 31 + b
    end
    "bg-avatar-#{(hash % 8) + 1} text-white"
  end

  # Helper method for styling CrawlerJob status badges
  def status_badge_class(status)
    case status
    when "pending", "queued_for_run"
      "bg-secondary"
    when "generating", "running"
      "bg-info text-dark" # Using text-dark for better contrast on info
    when "improving"
      "bg-warning text-dark"
    when "fixing"
      "bg-danger text-white"
    when "ready"
      "bg-primary"
    when "completed" # Assuming we add this status later
      "bg-success"
    when "failed"
      "bg-danger"
    else
      "bg-light text-dark" # Default/unknown status
    end
  end
end
