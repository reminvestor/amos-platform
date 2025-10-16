class GenerateImagesForLandingPageJob < ApplicationJob
  include JobErrorHandling

  queue_as :default

  # sizes_map: { '1200x600' => 'Hero banner', '100x100' => 'Feature icon' }
  def perform(landing_page_id, sizes_map = {}, user_id: nil, entity_id: nil)
    landing_page = LandingPage.find(landing_page_id)
    user = user_id ? User.find(user_id) : landing_page.user
    entity = entity_id ? Entity.find(entity_id) : landing_page.entity

    html = landing_page.html_content.to_s

    # Find placeholder images like 1200x600, 100x100, etc.
    placeholders = html.scan(/(https?:\/\/placehold\.co\/(\d+x\d+)[^"\s']*)/i).map { |m| m[1] }.uniq
    # Also capture raw text size markers sometimes present in mocks
    placeholders += html.scan(/(\d{2,4}x\d{2,4})/).flatten
    placeholders.uniq!

    return if placeholders.blank?

    service = ImageGenerationService.new
    replacements = {}

    placeholders.each do |size|
      human_title = sizes_map[size] || "Marketing image #{size}"
      description = "Professional marketing image, #{human_title}. Clean, modern, high-contrast."
      asset = service.generate_and_store!(user: user, entity: entity, title: human_title, description: description, size: size)
      replacements[size] = asset.url
    end

    updated_html = html.dup
    replacements.each do |size, url|
      updated_html.gsub!(%r{https?://placehold\.co/#{Regexp.escape(size)}[^"\s']*}i, url)
      # Replace bare text size hints inside style/background urls etc.
      updated_html.gsub!(/\b#{Regexp.escape(size)}\b/, url)
    end

    landing_page.update!(html_content: updated_html)
  end
end
