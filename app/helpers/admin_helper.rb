module AdminHelper
  # Generate a status badge with appropriate styling
  # @param status [String, Symbol] The status to display (e.g., 'active', 'completed', 'failed')
  # @param text [String] Optional custom text to display (defaults to uppercased status)
  # @return [String] HTML safe badge markup
  def admin_status_badge(status, text = nil)
    badge_class = case status.to_s.downcase
                  when 'active', 'in_progress', 'pending'
                    'admin-badge-warning'
                  when 'completed', 'success', 'online'
                    'admin-badge-online'
                  when 'failed', 'error', 'offline'
                    'admin-badge-offline'
                  when 'cancelled', 'canceled', 'inactive'
                    'admin-badge-default'
                  else
                    'admin-badge-default'
                  end

    display_text = text || status.to_s.upcase
    content_tag(:span, display_text, class: "admin-badge #{badge_class}")
  end

  # Generate a type badge with custom color mapping
  # @param type [String] The type to display
  # @param mapping [Hash] Optional custom badge class mapping
  # @return [String] HTML safe badge markup
  def admin_type_badge(type, mapping = {})
    default_mapping = {
      'voice_immediate' => 'admin-badge-offline',
      'voice_followup' => 'admin-badge-warning',
      'analysis' => 'admin-badge-cyan',
      'background' => 'admin-badge-default'
    }

    badge_class = (mapping[type] || default_mapping[type] || 'admin-badge-default')
    content_tag(:span, type.humanize, class: "admin-badge #{badge_class}")
  end

  # Generate an icon with consistent sizing
  # @param icon_name [String] Lucide icon name
  # @param size [Symbol] Size: :sm, :md, :lg, :xl (default: :md)
  # @param options [Hash] Additional HTML attributes
  # @return [String] HTML safe icon markup
  def admin_icon(icon_name, size: :md, **options)
    size_class = "admin-icon-#{size}"
    options[:class] = [options[:class], size_class].compact.join(' ')
    options[:'aria-hidden'] = 'true' unless options.key?(:'aria-label')

    content_tag(:i, '', { 'data-lucide': icon_name }.merge(options))
  end

  # Generate a table caption for accessibility
  # @param text [String] Caption text
  # @return [String] HTML safe caption markup
  def admin_table_caption(text)
    content_tag(:caption, text, class: 'visually-hidden')
  end

  # Format duration in milliseconds to human readable format
  # @param duration_ms [Numeric] Duration in milliseconds
  # @return [String] Formatted duration
  def format_duration_ms(duration_ms)
    return 'N/A' if duration_ms.nil?

    if duration_ms < 1000
      "#{duration_ms}ms"
    elsif duration_ms < 60000
      "#{(duration_ms / 1000.0).round(1)}s"
    else
      "#{(duration_ms / 60000.0).round(1)}m"
    end
  end

  # Generate an accessible button/link with icon
  # @param text [String] Button text
  # @param url [String] URL for link
  # @param icon [String] Optional Lucide icon name
  # @param options [Hash] Additional link_to options
  # @return [String] HTML safe link markup
  def admin_button_with_icon(text, url, icon: nil, **options)
    options[:class] = [options[:class], 'admin-btn'].compact.join(' ')

    link_to(url, options) do
      content = ''
      content += content_tag(:i, '', 'data-lucide': icon, 'aria-hidden': 'true') + ' ' if icon
      content += content_tag(:span, text)
      content.html_safe
    end
  end
end
