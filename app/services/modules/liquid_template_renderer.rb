# frozen_string_literal: true

# Modules::LiquidTemplateRenderer
#
# Renders Liquid templates for website pages bound to module data.
# Provides safe, sandboxed access to module records via Liquid drops.
#
# Usage:
#   renderer = Modules::LiquidTemplateRenderer.new(entity: entity)
#   html = renderer.render(
#     template_string: "{% for product in products %}<h2>{{ product.name }}</h2>{% endfor %}",
#     module_data: { "products" => records },
#     page_data: { "title" => "Catalog", "site_name" => "My Store" }
#   )
#
module Modules
  class LiquidTemplateRenderer
    # Custom Liquid filters for common formatting needs
    module TemplateFilters
      def currency(input, symbol = "$")
        return "" if input.nil?
        "#{symbol}#{format('%.2f', input.to_f)}"
      end

      def truncate_words(input, max_words = 20, ellipsis = "...")
        return "" if input.nil?
        words = input.to_s.split
        if words.length > max_words
          words.first(max_words).join(" ") + ellipsis
        else
          input.to_s
        end
      end

      def relative_time(input)
        return "" if input.nil?
        time = input.is_a?(Time) ? input : Time.parse(input.to_s)
        diff = Time.current - time
        case diff.abs
        when 0..59 then "just now"
        when 60..3599 then "#{(diff / 60).to_i} minutes ago"
        when 3600..86399 then "#{(diff / 3600).to_i} hours ago"
        when 86400..604799 then "#{(diff / 86400).to_i} days ago"
        else time.strftime("%b %d, %Y")
        end
      rescue
        input.to_s
      end

      def status_badge(input)
        return "" if input.nil?
        color = case input.to_s.downcase
                when "active", "published", "completed", "done", "success" then "success"
                when "pending", "in_progress", "processing", "warning" then "warning"
                when "draft", "inactive", "todo", "new" then "secondary"
                when "urgent", "critical", "error", "failed", "cancelled" then "danger"
                when "open", "started", "info" then "primary"
                else "secondary"
                end
        "<span class=\"badge bg-#{color}\">#{input}</span>"
      end

      def format_date(input, format_str = "%b %d, %Y")
        return "" if input.nil?
        time = input.is_a?(Time) ? input : Time.parse(input.to_s)
        time.strftime(format_str)
      rescue
        input.to_s
      end

      def json(input)
        input.to_json
      rescue
        "{}"
      end

      def default(input, default_value = "")
        input.present? ? input : default_value
      end

      def pluralize(input, singular, plural)
        input.to_i == 1 ? singular : plural
      end

      def markdown(input)
        return "" if input.nil?
        # Simple markdown-to-HTML (bold, italic, links, paragraphs)
        text = input.to_s
        text = text.gsub(/\*\*(.+?)\*\*/, '<strong>\1</strong>')
        text = text.gsub(/\*(.+?)\*/, '<em>\1</em>')
        text = text.gsub(/\[(.+?)\]\((.+?)\)/, '<a href="\2">\1</a>')
        text = text.gsub(/\n\n/, '</p><p>')
        "<p>#{text}</p>"
      end
    end

    def initialize(entity:)
      @entity = entity
    end

    # Render a Liquid template string with data
    #
    # @param template_string [String] The Liquid template to render
    # @param module_data [Hash] Module records keyed by collection name (e.g., { "products" => [...] })
    # @param page_data [Hash] Page-level variables (title, site_name, etc.)
    # @return [String] Rendered HTML
    def render(template_string:, module_data: {}, page_data: {})
      return "" if template_string.blank?

      template = Liquid::Template.parse(template_string)

      # Build the Liquid context with drops for safe access
      context = build_context(module_data, page_data)

      # Register custom filters
      template.render(context, filters: [TemplateFilters], strict_variables: false)
    rescue Liquid::SyntaxError => e
      Rails.logger.error "[LiquidTemplateRenderer] Syntax error: #{e.message}"
      "<div class='alert alert-danger'>Template error: #{e.message}</div>"
    rescue => e
      Rails.logger.error "[LiquidTemplateRenderer] Render error: #{e.message}"
      "<div class='alert alert-warning'>Unable to render template</div>"
    end

    # Render a WebsitePage with its module data
    #
    # @param page [WebsitePage] The page to render
    # @param params [Hash] Request params (for filtering, pagination, record lookup)
    # @return [String] Rendered HTML content
    def render_page(page, params: {})
      template_content = page.html_content
      return "" if template_content.blank?

      module_data = {}
      page_data = build_page_data(page)

      if page.dynamic? && page.app_module.present?
        collection_name = page.app_module.slug.pluralize
        model_name = page.app_module.slug.singularize

        if params[:id].present? || params[:slug].present?
          # Single record view
          record = page.fetch_single_record(params[:id] || params[:slug])
          if record
            module_data[model_name] = ModuleRecordDrop.new(record)
            module_data["record"] = ModuleRecordDrop.new(record)
          end
        else
          # Collection view
          records = page.fetch_module_data(params)
          module_data[collection_name] = records.map { |r| ModuleRecordDrop.new(r) }
          module_data["records"] = module_data[collection_name]
          module_data["record_count"] = records.length
        end

        # Add schema info for form generation
        schema = page.app_module.metadata&.dig("schema")
        module_data["schema"] = schema if schema
      end

      render(template_string: template_content, module_data: module_data, page_data: page_data)
    end

    private

    def build_context(module_data, page_data)
      context = {}

      # Add page-level data
      page_data.each do |key, value|
        context[key.to_s] = value
      end

      # Add module data (already wrapped in drops or primitives)
      module_data.each do |key, value|
        context[key.to_s] = value
      end

      # Add global helpers
      context["current_year"] = Time.current.year
      context["current_date"] = Time.current.strftime("%B %d, %Y")
      context["entity_name"] = @entity&.name

      context
    end

    def build_page_data(page)
      {
        "title" => page.name,
        "description" => page.description,
        "slug" => page.slug,
        "site_name" => page.website&.name,
        "site_url" => page.website&.public_url,
        "is_dynamic" => page.dynamic?,
        "module_slug" => page.app_module&.slug,
        "module_name" => page.app_module&.name
      }.compact
    end
  end

  # ============================================
  # LIQUID DROPS — Safe accessors for module records
  # ============================================

  # Drop that wraps a single module record for safe Liquid access
  class ModuleRecordDrop < Liquid::Drop
    def initialize(record)
      @record = record
    end

    # Allow Liquid to access any attribute by name
    def liquid_method_missing(method)
      if @record.respond_to?(method)
        value = @record.send(method)
        # Wrap associated records in drops too
        if value.is_a?(ActiveRecord::Base)
          ModuleRecordDrop.new(value)
        elsif value.is_a?(ActiveRecord::Relation) || (value.is_a?(Array) && value.first.is_a?(ActiveRecord::Base))
          value.map { |r| ModuleRecordDrop.new(r) }
        else
          value
        end
      elsif @record.respond_to?(:attributes) && @record.attributes.key?(method.to_s)
        @record.attributes[method.to_s]
      elsif @record.is_a?(Hash)
        @record[method.to_s] || @record[method.to_sym]
      end
    end

    def to_s
      @record.respond_to?(:name) ? @record.name.to_s : @record.to_s
    end

    def id
      @record.respond_to?(:id) ? @record.id : nil
    end
  end
end
