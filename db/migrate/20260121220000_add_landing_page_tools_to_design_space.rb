# frozen_string_literal: true

class AddLandingPageToolsToDesignSpace < ActiveRecord::Migration[7.0]
  def up
    # Find the design space definition
    design_space = execute("SELECT id, default_tool_loadout FROM space_definitions WHERE slug = 'design' LIMIT 1").first
    return unless design_space

    # Parse existing tools
    existing_tools = design_space['default_tool_loadout']
    if existing_tools.is_a?(String)
      existing_tools = JSON.parse(existing_tools) rescue []
    end
    existing_tools ||= []

    # Required tools for landing page editing
    required_tools = %w[
      update_landing_page_content
      edit_landing_page_section
      read_landing_page_sections
      generate_landing_page
      create_object
      update_object
      get_data
      get_schema
    ]

    # Add missing tools
    updated_tools = (existing_tools + required_tools).uniq

    # Update the space definition
    execute <<-SQL
      UPDATE space_definitions 
      SET default_tool_loadout = '#{updated_tools.to_json}'
      WHERE slug = 'design'
    SQL

    puts "✅ Updated design space with landing page tools: #{required_tools.join(', ')}"
  end

  def down
    # No rollback needed - tools can remain
  end
end
