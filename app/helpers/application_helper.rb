module ApplicationHelper
  # ===== SPACE-AWARE SIDEBAR HELPERS =====
  
  # Define which sidebar sections are visible in each space
  SIDEBAR_SPACE_CONFIG = {
    'personal' => {
      visible_sections: %w[documents tasks notes bookmarks reminders media ai],
      hidden_sections: %w[marketing contacts sales integrations agents settings]
    },
    'work' => {
      visible_sections: %w[marketing contacts sales media ai settings agents integrations tasks],
      hidden_sections: %w[notes bookmarks reminders]
    },
    'team' => {
      visible_sections: %w[marketing contacts sales media ai settings agents integrations tasks],
      hidden_sections: %w[notes bookmarks reminders]
    }
  }.freeze

  def sidebar_section_visible?(section_name)
    return true unless current_user.respond_to?(:active_space)
    
    space = current_user.active_space || 'work'
    config = SIDEBAR_SPACE_CONFIG[space] || SIDEBAR_SPACE_CONFIG['work']
    
    # If explicitly hidden, return false
    return false if config[:hidden_sections]&.include?(section_name)
    
    # If visible_sections defined and section not in it, return false
    if config[:visible_sections].present?
      return config[:visible_sections].include?(section_name) || 
             !%w[personal work team].include?(space) # Default to show for unknown spaces
    end
    
    true
  end

  def current_space_name
    return 'Work' unless current_user.respond_to?(:active_space)
    
    space = current_user.active_space || 'work'
    space.titleize
  end

  def current_space_icon
    return 'briefcase' unless current_user.respond_to?(:active_space)
    
    case current_user.active_space
    when 'personal' then 'user'
    when 'team' then 'users'
    else 'briefcase'
    end
  end

  # ===== END SPACE-AWARE SIDEBAR HELPERS =====

  # Helper for team role badges
  def role_badge_class(role)
    case role.to_s
    when 'owner'
      'bg-primary'
    when 'admin'
      'bg-info'
    when 'member'
      'bg-secondary'
    else
      'bg-light text-dark'
    end
  end

  # Helper methods for parallel task monitoring
  def task_type_color(task_type)
    case task_type.to_s
    when 'voice_immediate'
      'danger'
    when 'voice_followup'
      'warning'
    when 'analysis'
      'primary'
    when 'background'
      'secondary'
    else
      'info'
    end
  end
  
  def format_duration(seconds)
    return '-' if seconds.nil? || seconds < 0
    
    if seconds < 60
      "#{seconds.round(1)}s"
    elsif seconds < 3600
      minutes = (seconds / 60).floor
      secs = (seconds % 60).round
      "#{minutes}m #{secs}s"
    else
      hours = (seconds / 3600).floor
      minutes = ((seconds % 3600) / 60).floor
      "#{hours}h #{minutes}m"
    end
  end
  
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

  # Sanitize user/AI-generated HTML content
  def safe_html(content)
    return "" if content.blank?

    sanitize(
      content,
      tags: %w[p h1 h2 h3 h4 h5 h6 em strong b i u br hr ul ol li div span a img blockquote code pre table thead tbody tr th td],
      attributes: {
        'a' => ['href', 'title', 'target', 'rel'],
        'img' => ['src', 'alt', 'width', 'height', 'loading'],
        'div' => ['class', 'id'],
        'span' => ['class', 'id'],
        'table' => ['class'],
        'td' => ['colspan', 'rowspan'],
        'th' => ['colspan', 'rowspan'],
        '*' => ['class', 'id']
      }
    )
  end

  def markdown(text)
    return "" if text.blank?

    # Initialize Redcarpet Markdown renderer
    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      filter_html: true,  # SECURITY: Filter raw HTML in markdown
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

    # Process the markdown and sanitize output
    safe_html(markdown.render(text))
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
