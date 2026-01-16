# frozen_string_literal: true

class UpdatePersonalSpaceToolLoadout < ActiveRecord::Migration[7.1]
  def up
    personal_space = SpaceDefinition.find_by(slug: 'personal')
    return unless personal_space

    # Updated Personal space tools: Conversation, research, memory, personal productivity
    # EXCLUDED: Campaigns, landing pages, integrations, business analytics, module building
    personal_space.update!(
      default_tool_loadout: %w[
        ask_user
        web_search
        view_web_page
        generate_image
        create_freeform_canvas
        remember_this
        recall_context
        search_memory
        list_saved
        bookmark_this
        retrieve_history
        search_history
        query_document_content
        read_document
        create_scheduled_task
        list_scheduled_tasks
        manage_scheduled_task
        get_work_inbox
        list_available_agents
        delegate_to_agent
        find_best_agent
        deep_reasoning
      ]
    )

    puts "✅ Updated Personal space tool loadout"
  end

  def down
    personal_space = SpaceDefinition.find_by(slug: 'personal')
    return unless personal_space

    # Revert to original limited set
    personal_space.update!(
      default_tool_loadout: %w[
        get_work_inbox
        create_scheduled_task
        list_scheduled_tasks
        manage_scheduled_task
        remember_this
        recall_context
        search_memory
        list_saved
        web_search
        view_web_page
      ]
    )
  end
end

