# frozen_string_literal: true

class CreateModuleActions < ActiveRecord::Migration[7.0]
  def change
    create_table :module_actions do |t|
      t.references :app_module, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      t.string :name, null: false
      t.string :slug, null: false
      t.string :icon, default: 'play'
      t.string :style, default: 'primary'  # primary, secondary, success, danger, warning, outline
      t.string :location, default: 'toolbar'  # toolbar, row, field, form_footer
      t.string :target_field  # For field-level actions (e.g., AI assist on content field)
      
      t.integer :position, default: 0  # Display order
      
      # Visibility conditions
      t.jsonb :show_when, default: {}
      # { field: 'status', equals: 'draft' }
      # { field: 'status', in: ['draft', 'pending'] }
      # { setting: 'approval_enabled', equals: true }
      
      # Permissions
      t.jsonb :requires_role, default: {}
      # { role: 'approver' } or { permission: 'can_publish' }
      
      # Behavior configuration
      t.string :behavior_type, null: false
      # update, update_and_notify, modal_form, navigate, call_tool, 
      # agent_assist, run_workflow, confirm, custom
      
      t.jsonb :behavior_config, default: {}
      # Depends on behavior_type:
      # update: { updates: { status: 'approved' } }
      # modal_form: { fields: ['notes'], on_submit: { type: 'update', updates: {} } }
      # call_tool: { tool: 'publish_post', params: { post_id: '$record.id' } }
      # agent_assist: { agent: 'app_assistant', prompt: 'Help write this' }
      
      t.boolean :active, default: true
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :module_actions, [:app_module_id, :slug], unique: true
    add_index :module_actions, :location
    add_index :module_actions, :active
  end
end





