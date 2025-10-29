module Admin::SystemDocumentsHelper
  def icon_for_content_type(content_type)
    icon_class = case content_type
                 when 'application/pdf'
                   'fa-file-pdf text-danger'
                 when /word/
                   'fa-file-word text-primary'
                 when 'text/markdown'
                   'fa-file-code text-info'
                 when /powerpoint|presentation/
                   'fa-file-powerpoint text-warning'
                 when /^text\//
                   'fa-file-alt text-secondary'
                 else
                   'fa-file text-muted'
                 end

    content_tag(:i, '', class: "fas #{icon_class} me-2")
  end

  def status_badge_for_system_document(document)
    badge_class, icon, text = case document.status
                               when 'pending'
                                 ['bg-secondary', 'clock', 'Pending']
                               when 'processing'
                                 ['bg-warning', 'spinner fa-spin', 'Processing...']
                               when 'indexed'
                                 ['bg-success', 'check-circle', 'Indexed']
                               when 'failed'
                                 ['bg-danger', 'exclamation-circle', 'Failed']
                               else
                                 ['bg-secondary', 'question', 'Unknown']
                               end

    content_tag(:span, class: "badge #{badge_class}") do
      concat content_tag(:i, '', class: "fas fa-#{icon} me-1")
      concat text
    end
  end
end
