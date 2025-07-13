module WorkspaceHelper
  def calculate_open_rate(entity)
    total_sent = entity.campaigns.sum(:sent_count) || 0
    total_opened = entity.campaigns.sum(:opened_count) || 0
    return 0 if total_sent == 0
    ((total_opened.to_f / total_sent) * 100).round(1)
  end
  
  def calculate_click_rate(entity)
    total_sent = entity.campaigns.sum(:sent_count) || 0
    total_clicked = entity.campaigns.sum(:clicked_count) || 0
    return 0 if total_sent == 0
    ((total_clicked.to_f / total_sent) * 100).round(1)
  end
end
