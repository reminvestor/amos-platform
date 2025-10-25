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
        ai: '<i class="fas fa-brain"></i>',
        voice: '<i class="fas fa-microphone"></i>',
        integrations: '<i class="fas fa-plug"></i>',
        infrastructure: '<i class="fas fa-server"></i>',
        email: '<i class="fas fa-envelope"></i>'
      }
      icons[category]&.html_safe || '<i class="fas fa-cog"></i>'.html_safe
    end
  end
end
