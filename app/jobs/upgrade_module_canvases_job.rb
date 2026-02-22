# frozen_string_literal: true

# Upgrades module canvases from static templates to AI-generated versions.
# Queued automatically after ApplicationBuildService completes so the build
# itself stays fast (~seconds) while richer canvases arrive in the background.
class UpgradeModuleCanvasesJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 2

  def perform(app_module_id)
    app_module = AppModule.find_by(id: app_module_id)
    return unless app_module

    entity = app_module.entity
    user = app_module.created_by || entity.users.first
    return unless entity && user

    fields = (app_module.metadata&.dig("schema", "fields") || [])
    related_models = build_related_models(app_module)

    generator = CanvasGeneratorService.new(entity: entity, user: user)

    app_module.module_canvases.where("metadata->>'ai_upgrade_pending' = ?", "true").find_each do |canvas|
      next if canvas.locked?

      view_type = canvas.slug.sub("#{app_module.slug}_", "")
      Rails.logger.info "[UpgradeCanvases] Upgrading #{app_module.name}/#{view_type}"

      result = generator.generate(
        app_module: app_module,
        view_type: view_type,
        fields: fields,
        related_models: related_models
      )

      next unless result[:html].present?

      canvas.update!(
        html_content: result[:html],
        js_content: result[:js],
        css_content: result[:css],
        metadata: canvas.metadata.merge(
          "generated_by" => "canvas_generator",
          "ai_upgrade_pending" => false,
          "upgraded_at" => Time.current.iso8601
        )
      )
    end

    Rails.logger.info "[UpgradeCanvases] Completed for #{app_module.name}"
  end

  private

  def build_related_models(app_module)
    related = []
    associations = app_module.module_codes
                             .where(code_type: "model")
                             .flat_map { |mc| mc.schema_definition&.dig("associations") || [] }

    associations.each do |assoc|
      related << {
        name: assoc["model"]&.titleize || assoc["table"]&.singularize&.titleize,
        relationship_type: assoc["type"],
        slug: assoc["table"]&.singularize
      }
    end

    related
  end
end
