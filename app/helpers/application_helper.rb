module ApplicationHelper
  # ===== SPACE-AWARE SIDEBAR HELPERS =====
  
  # Map section names (used in sidebar) to menu item slugs (used in menu config)
  # A section is visible if ANY of its items are visible
  SECTION_TO_ITEMS = {
    'marketing' => %w[landing_pages campaigns email_templates],
    'contacts' => %w[contacts contact_groups],
    'sales' => %w[analytics saved_visualizations pipeline pipeline_viewer],
    'tasks' => %w[tasks work_inbox scheduled_tasks parallel_tasks],
    'notes' => %w[notes],
    'bookmarks' => %w[bookmarks],
    'reminders' => %w[reminders],
    'documents' => %w[documents document_viewer document_search_results],
    'integrations' => %w[integrations integrations_manager],
    'agents' => %w[agents agent_marketplace],
    'channels' => %w[team_channels],
    'ai' => %w[ai],
    'settings' => %w[settings],
    'media' => %w[media image_assets],
    'dashboard' => %w[dashboard],
    'platform' => %w[execution_dashboard],
    'apps' => %w[apps my_creations module_manager]
  }.freeze
  
  # Default sections visible in each space (used as fallback if no user config)
  DEFAULT_SPACE_SECTIONS = {
    'personal' => {
      visible_sections: %w[documents tasks notes bookmarks reminders media ai],
      hidden_sections: %w[marketing contacts sales integrations agents settings channels dashboard platform apps]
    },
    'work' => {
      visible_sections: %w[dashboard marketing contacts sales media ai settings agents integrations tasks platform apps],
      hidden_sections: %w[notes bookmarks reminders channels]
    },
    'team' => {
      visible_sections: %w[channels ai agents settings],
      hidden_sections: %w[marketing contacts sales notes bookmarks reminders integrations tasks media dashboard platform apps]
    }
  }.freeze

  # Sections that should ALWAYS be visible regardless of user config
  ALWAYS_VISIBLE_SECTIONS = %w[ai settings tasks media].freeze
  
  # Items that should ALWAYS be visible regardless of user config
  ALWAYS_VISIBLE_ITEMS = %w[tasks work_items].freeze
  
  # Check if a specific menu item is visible (for individual item checks)
  def sidebar_item_visible?(item_slug)
    item = item_slug.to_s
    
    # Always visible items
    return true if ALWAYS_VISIBLE_ITEMS.include?(item)
    
    return true unless current_user.respond_to?(:active_space)
    
    space = current_user.active_space || 'work'
    
    # Check user's menu config
    if current_user.respond_to?(:menu_config_for_space)
      user_config = current_user.menu_config_for_space(space)
      
      if user_config.present?
        hidden = (user_config.hidden_items || []).map(&:to_s)
        visible = (user_config.visible_items || []).map(&:to_s)
        
        # If user has configured anything
        if hidden.any? || visible.any?
          # If item is in hidden list, hide it
          return false if hidden.include?(item)
          
          # If visible list exists, item must be in it
          if visible.any?
            return visible.include?(item)
          end
        end
      end
    end
    
    # Fall back to default space config (check if section containing this item is visible)
    config = DEFAULT_SPACE_SECTIONS[space] || DEFAULT_SPACE_SECTIONS['work']
    
    # Find which section this item belongs to
    section = SECTION_TO_ITEMS.find { |_sec, items| items.include?(item) }&.first
    
    return true if section.nil? # Unknown item, show by default
    
    # Check section visibility in defaults
    return false if config[:hidden_sections]&.include?(section)
    return config[:visible_sections]&.include?(section) if config[:visible_sections].present?
    
    true
  end
  
  def sidebar_section_visible?(section_name)
    # AI, Settings, and Tasks are always visible - never hide them
    return true if ALWAYS_VISIBLE_SECTIONS.include?(section_name.to_s)

    return true unless current_user.respond_to?(:active_space)
    
    space = current_user.active_space || 'work'
    
    # Get the items that belong to this section
    section_items = SECTION_TO_ITEMS[section_name.to_s] || [section_name.to_s]
    
    # Check user's custom menu configuration
    if current_user.respond_to?(:menu_config_for_space)
      user_config = current_user.menu_config_for_space(space)
      
      if user_config.present?
        hidden = user_config.hidden_items || []
        visible = user_config.visible_items || []
        
        # Convert to strings for comparison (in case of symbol/string mismatch)
        hidden_strs = hidden.map(&:to_s)
        visible_strs = visible.map(&:to_s)
        section_strs = section_items.map(&:to_s)
        
        # If user has configured anything (either list is non-empty)
        if hidden_strs.any? || visible_strs.any?
          # If ALL section items are hidden, hide the section
          if hidden_strs.any?
            all_hidden = section_strs.all? { |item| hidden_strs.include?(item) }
            return false if all_hidden
          end
          
          # If visible list exists, section is visible only if ANY item is in visible list
          if visible_strs.any?
            any_visible = section_strs.any? { |item| visible_strs.include?(item) }
            return any_visible
          end
        end
      end
    end
    
    # Fall back to default space config
    config = DEFAULT_SPACE_SECTIONS[space] || DEFAULT_SPACE_SECTIONS['work']
    
    # If explicitly hidden in defaults, return false
    return false if config[:hidden_sections]&.include?(section_name.to_s)
    
    # If visible_sections defined and section not in it, return false
    if config[:visible_sections].present?
      return config[:visible_sections].include?(section_name.to_s) || 
             !%w[personal work team].include?(space)
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
  
  # Helper for bounty status colors
  def bounty_status_color(status)
    case status.to_s
    when "open"
      "success"
    when "claimed", "in_progress"
      "warning"
    when "pending_review"
      "info"
    when "completed", "approved"
      "primary"
    when "rejected", "expired"
      "danger"
    else
      "secondary"
    end
  end
  
  # Helper for referral status badges
  def referral_status_badge(status)
    case status.to_s
    when "pending"
      "warning"
    when "signed_up", "active"
      "success"
    when "converted"
      "primary"
    when "expired"
      "secondary"
    else
      "secondary"
    end
  end
  
  # Helper to check if wallet is connected (for gov/build portals)
  def wallet_connected?
    session[:solana_wallet].present?
  end
  
  # Helper to get AMOS balance
  def amos_balance
    return 0 unless current_user&.token_stake.present?
    current_user.token_stake.current_balance
  rescue
    0
  end
end
