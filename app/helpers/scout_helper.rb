# frozen_string_literal: true

module ScoutHelper
  # Helper for section icons in the App Designer canvas
  def section_icon(type)
    icon_name = case type.to_s
    when 'hero' then 'layout-template'
    when 'features' then 'grid-3x3'
    when 'benefits' then 'check-circle'
    when 'testimonials' then 'quote'
    when 'pricing' then 'credit-card'
    when 'cta' then 'megaphone'
    when 'contact' then 'mail'
    when 'about' then 'users'
    when 'gallery' then 'images'
    when 'faq' then 'help-circle'
    when 'stats' then 'bar-chart-2'
    when 'team' then 'user'
    when 'footer' then 'panel-bottom'
    else 'square'
    end

    content_tag(:i, '', 'data-lucide': icon_name, style: 'width: 14px; height: 14px;')
  end
end
