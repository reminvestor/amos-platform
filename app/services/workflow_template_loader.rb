class WorkflowTemplateLoader
  class << self
    def load_all
      template_files = Dir[Rails.root.join("app/workflow_templates/*.yml")]

      template_files.map do |file|
        load_template_file(file)
      end.compact
    end

    def load_all_v2
      template_files = Dir[Rails.root.join("app/workflow_templates/*_v2.yml")]

      template_files.map do |file|
        load_v2_template_file(file)
      end.compact
    end

    def load_template(slug)
      file_path = Rails.root.join("app/workflow_templates/#{slug}.yml")
      return nil unless File.exist?(file_path)

      load_template_file(file_path)
    end

    def load_v2_template(slug)
      file_path = Rails.root.join("app/workflow_templates/#{slug}.yml")
      return nil unless File.exist?(file_path)

      load_v2_template_file(file_path)
    end

    def load_template_by_slug(slug)
      # Try loading as V2 template (our only version now)
      # First try with _v2 suffix
      file_path = Rails.root.join("app/workflow_templates/#{slug}_v2.yml")

      # If not found, try without suffix (for backward compatibility)
      unless File.exist?(file_path)
        file_path = Rails.root.join("app/workflow_templates/#{slug}.yml")
      end

      return nil unless File.exist?(file_path)

      load_v2_template_file(file_path)
    end

    def list_all_templates
      # Get all V2 templates with basic info for LLM
      template_files = Dir[Rails.root.join("app/workflow_templates/*_v2.yml")]

      template_files.map do |file|
        yaml_content = YAML.load_file(file)
        {
          slug: yaml_content["slug"],
          name: yaml_content["name"],
          description: yaml_content["description"],
          category: yaml_content["category"],
          industry: yaml_content["industry"],
          tags: yaml_content["tags"] || [],
          version: yaml_content["template_version"] || 2
        }
      end.compact
    rescue => e
      Rails.logger.error "Failed to list templates: #{e.message}"
      []
    end

    private

    def load_template_file(file_path)
      yaml_content = YAML.load_file(file_path)

      # Convert YAML to WorkflowTemplate format
      {
        name: yaml_content["name"],
        slug: yaml_content["slug"],
        description: yaml_content["description"],
        category: yaml_content["category"],
        industry: yaml_content["industry"],
        tags: yaml_content["tags"] || [],
        metadata: {
          keywords: yaml_content["keywords"] || [],
          validation: yaml_content["validation"] || {}
        },
        template_spec: {
          steps: yaml_content["steps"].map { |step| convert_step(step) }
        },
        is_active: true,
        is_system: true
      }
    rescue => e
      Rails.logger.error "Failed to load workflow template #{file_path}: #{e.message}"
      nil
    end

    def convert_step(step_yaml)
      {
        id: step_yaml["id"],
        name: step_yaml["name"],
        description: step_yaml["description"],
        agent_role: step_yaml["agent_role"],
        type: step_yaml["type"],
        config: build_step_config(step_yaml),
        dependencies: step_yaml["dependencies"] || [],
        tool_allowlist: step_yaml["required_tools"] || [],
        canvas_allowlist: step_yaml["canvas_allowlist"] || [],
        budgets: step_yaml["budgets"] || {}
      }
    end

    def build_step_config(step_yaml)
      config = {}

      case step_yaml["type"]
      when "tool_call"
        config[:tool] = step_yaml["tool"]
        config[:tool_args] = step_yaml["tool_args"] || {}
      when "user_input"
        config[:form] = step_yaml["form"]
      when "decision"
        config[:options] = step_yaml["options"]
      end

      # Merge any additional config from the YAML
      if step_yaml["config"].is_a?(Hash)
        config.merge!(step_yaml["config"].symbolize_keys)
      end

      config
    end

    def load_v2_template_file(file_path)
      yaml_content = YAML.load_file(file_path)

      # V2 templates are stored as-is (they have their own structure)
      {
        name: yaml_content["name"],
        slug: yaml_content["slug"],
        description: yaml_content["description"],
        category: yaml_content["category"],
        industry: yaml_content["industry"],
        tags: yaml_content["tags"] || [],
        template_spec: yaml_content.symbolize_keys,  # Entire YAML as spec
        is_active: true,
        is_system: true
      }
    rescue => e
      Rails.logger.error "Failed to load V2 workflow template #{file_path}: #{e.message}"
      nil
    end
  end
end
