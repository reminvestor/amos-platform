# frozen_string_literal: true

class UpdatePersonalSpaceMenuItems < ActiveRecord::Migration[7.1]
  def up
    personal_space = SpaceDefinition.find_by(slug: 'personal')
    return unless personal_space

    # Personal space menu: Personal productivity items only
    # No business items (campaigns, landing pages, contacts, analytics, etc.)
    new_menu_items = %w[
      notes
      bookmarks
      reminders
      tasks
      work_inbox
      documents
      document_viewer
      image_assets
    ]
    
    personal_space.update!(default_menu_items: new_menu_items)

    # Reset all existing user menu configs for personal space to use new defaults
    # This ensures users get the updated personal-friendly menu
    reset_count = 0
    UserMenuConfiguration.where(space: 'personal').find_each do |config|
      config.update!(
        visible_items: new_menu_items,
        hidden_items: []
      )
      reset_count += 1
    end

    puts "✅ Updated Personal space menu items"
    puts "✅ Reset #{reset_count} user menu configurations for personal space"
  end

  def down
    personal_space = SpaceDefinition.find_by(slug: 'personal')
    return unless personal_space

    personal_space.update!(
      default_menu_items: %w[
        tasks
        work_items
        reminders
        notes
        documents
      ]
    )
  end
end

