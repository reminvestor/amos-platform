# app/helpers/admin/entity_costs_helper.rb
module Admin::EntityCostsHelper
  def format_cost(amount)
    number_to_currency(amount, precision: 2)
  end

  def cost_trend_icon(trend)
    case trend
    when 'increasing'
      content_tag(:i, '', class: 'text-danger', data: { lucide: 'arrow-up' })
    when 'decreasing'
      content_tag(:i, '', class: 'text-success', data: { lucide: 'arrow-down' })
    else
      content_tag(:i, '', class: 'text-secondary', data: { lucide: 'minus' })
    end
  end

  def cost_badge_color(percentage)
    case percentage
    when 0..50
      'success'
    when 51..80
      'warning'
    when 81..100
      'danger'
    else
      'danger'
    end
  end

  def tier_badge_color(tier)
    case tier
    when 'premium'
      'primary'
    when 'standard'
      'info'
    when 'starter'
      'warning'
    when 'free'
      'secondary'
    else
      'light'
    end
  end

  def format_percentage_change(current, previous)
    return 'N/A' if previous.nil? || previous.zero?

    change = ((current - previous) / previous * 100).round(1)

    if change > 0
      content_tag(:span, "+#{change}%", class: 'text-danger')
    elsif change < 0
      content_tag(:span, "#{change}%", class: 'text-success')
    else
      content_tag(:span, "0%", class: 'text-muted')
    end
  end

  def format_service_name(service)
    service.to_s.split('_').map(&:capitalize).join(' ')
  end

  def cost_chart_colors
    [
      '#0d6efd', # primary blue
      '#6610f2', # indigo
      '#6f42c1', # purple
      '#d63384', # pink
      '#dc3545', # danger red
      '#fd7e14', # orange
      '#ffc107', # warning yellow
      '#28a745', # success green
      '#20c997', # teal
      '#17a2b8'  # info cyan
    ]
  end

  def threshold_alert_class(overage_percent)
    if overage_percent > 50
      'alert-danger'
    elsif overage_percent > 25
      'alert-warning'
    else
      'alert-info'
    end
  end

  def format_date_range(start_date, end_date)
    if start_date.month == end_date.month && start_date.year == end_date.year
      "#{start_date.strftime('%b %d')} - #{end_date.strftime('%d, %Y')}"
    elsif start_date.year == end_date.year
      "#{start_date.strftime('%b %d')} - #{end_date.strftime('%b %d, %Y')}"
    else
      "#{start_date.strftime('%b %d, %Y')} - #{end_date.strftime('%b %d, %Y')}"
    end
  end

  def cost_category_icon(category)
    icons = {
      'ai_chat' => 'bot',
      'email' => 'mail',
      'sms' => 'message-circle',
      'storage' => 'database',
      'compute' => 'cpu',
      'bandwidth' => 'wifi',
      'integration' => 'plug',
      'other' => 'more-horizontal'
    }

    icons[category.to_s] || 'help-circle'
  end
end