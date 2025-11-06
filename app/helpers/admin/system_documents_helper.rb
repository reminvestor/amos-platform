module Admin::SystemDocumentsHelper
  def icon_for_content_type(content_type)
    icon, color = case content_type
                  when 'application/pdf'
                    ['file-pdf', 'text-danger']
                  when /word/
                    ['file-text', 'text-primary']
                  when 'text/markdown'
                    ['code', 'text-info']
                  when /powerpoint|presentation/
                    ['file-text', 'text-warning']
                  when /^text\//
                    ['file-text', 'text-secondary']
                  else
                    ['file', 'text-muted']
                  end

    content_tag(:i, '', class: "me-2 #{color}", data: { lucide: icon })
  end

  def status_badge_for_system_document(document)
    badge_class, icon, text = case document.status
                               when 'pending'
                                 ['bg-secondary', 'clock', 'Pending']
                               when 'processing'
                                 ['bg-warning', 'loader', 'Processing...']
                               when 'indexed'
                                 ['bg-success', 'check-circle', 'Indexed']
                               when 'failed'
                                 ['bg-danger', 'alert-circle', 'Failed']
                               else
                                 ['bg-secondary', 'help-circle', 'Unknown']
                               end

    content_tag(:span, class: "badge #{badge_class}") do
      concat content_tag(:i, '', class: "me-1", data: { lucide: icon })
      concat text
    end
  end
end
