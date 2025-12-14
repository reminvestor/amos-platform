# frozen_string_literal: true

module HubHelper
  def presence_class_for(participant)
    presence = if participant.is_a?(User)
                 HubPresence.find_by(participant: participant)
               elsif participant.respond_to?(:hub_presence)
                 participant.hub_presence
               end

    return 'offline' unless presence

    case presence.status
    when 'online' then 'online'
    when 'away' then 'away'
    when 'busy', 'working', 'thinking' then 'busy'
    when 'waiting' then 'away'
    else 'offline'
    end
  end

  def presence_status_text(participant)
    presence = if participant.is_a?(User)
                 HubPresence.find_by(participant: participant)
               elsif participant.respond_to?(:hub_presence)
                 participant.hub_presence
               end

    return 'Offline' unless presence

    case presence.status
    when 'online' then 'Online'
    when 'away' then 'Away'
    when 'busy' then 'Busy'
    when 'working' then presence.current_activity.presence || 'Working'
    when 'thinking' then 'Thinking...'
    when 'waiting' then presence.current_activity.presence || 'Waiting for input'
    else 'Offline'
    end
  end

  def execution_status_class(status)
    case status
    when 'completed' then 'bg-success'
    when 'running' then 'bg-primary'
    when 'pending' then 'bg-secondary'
    when 'waiting_for_input' then 'bg-warning text-dark'
    when 'failed' then 'bg-danger'
    else 'bg-secondary'
    end
  end

  def message_time_display(message)
    if message.created_at.to_date == Date.current
      message.created_at.strftime('%l:%M %p')
    elsif message.created_at.to_date == Date.yesterday
      "Yesterday #{message.created_at.strftime('%l:%M %p')}"
    else
      message.created_at.strftime('%b %d, %l:%M %p')
    end
  end

  def format_hub_content(content)
    # Convert markdown-like formatting to HTML
    formatted = h(content)
    
    # Bold
    formatted = formatted.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
    
    # Code
    formatted = formatted.gsub(/`(.+?)`/, '<code>\1</code>')
    
    # Links
    formatted = formatted.gsub(/\[(.+?)\]\((.+?)\)/, '<a href="\2" target="_blank">\1</a>')
    
    # Mentions
    formatted = formatted.gsub(/@(\w+)/) do |match|
      "<span class=\"mention badge bg-primary-subtle text-primary\">#{match}</span>"
    end
    
    simple_format(formatted.html_safe)
  end

  def thread_icon(thread)
    case thread.thread_type
    when 'channel' then 'hash'
    when 'dm' then 'chat-dots'
    when 'work_stream' then 'layers'
    when 'agent_handoff' then 'arrow-left-right'
    else 'chat'
    end
  end

  def agent_status_badge(agent)
    presence = agent.hub_presence
    return content_tag(:span, 'Offline', class: 'badge bg-secondary') unless presence

    case presence.status
    when 'online'
      content_tag(:span, 'Ready', class: 'badge bg-success')
    when 'working', 'thinking'
      activity = presence.current_activity&.truncate(30) || 'Working'
      content_tag(:span, activity, class: 'badge bg-primary')
    when 'waiting'
      content_tag(:span, 'Waiting', class: 'badge bg-warning text-dark')
    else
      content_tag(:span, 'Offline', class: 'badge bg-secondary')
    end
  end

  def unread_badge(count)
    return '' unless count.to_i.positive?
    
    content_tag(:span, count > 99 ? '99+' : count, class: 'badge bg-danger ms-auto')
  end

  def handoff_urgency_class(urgency)
    case urgency
    when 'critical' then 'border-danger'
    when 'high' then 'border-warning'
    else 'border-primary'
    end
  end
end
