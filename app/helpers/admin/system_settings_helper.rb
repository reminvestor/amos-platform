module Admin
  module SystemSettingsHelper
    def category_color(category)
      colors = {
        ai: "bg-primary",
        voice: "bg-success",
        integrations: "bg-info",
        infrastructure: "bg-secondary",
        email: "bg-warning"
      }
      colors[category] || "bg-dark"
    end

    def category_icon(category)
      icons = {
        ai: 'brain',
        voice: 'microphone',
        integrations: 'plug',
        infrastructure: 'server',
        email: 'mail'
      }
      icon_name = icons[category] || 'settings'
      content_tag(:i, '', data: { lucide: icon_name })
    end
  end
end
