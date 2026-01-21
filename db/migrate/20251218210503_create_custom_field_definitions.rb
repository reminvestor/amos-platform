# frozen_string_literal: true

class CreateCustomFieldDefinitions < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_field_definitions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :app_module, null: true, foreign_key: true  # Optional - can be standalone
      
      # Target model
      t.string :model_type, null: false  # Contact, Campaign, LandingPage, or dynamic model name
      
      # Field definition
      t.string :field_name, null: false
      t.string :field_type, null: false  # string, integer, decimal, boolean, date, datetime, json, array, reference
      t.string :field_label  # Human-readable label
      t.text :field_description
      
      # Display configuration
      t.string :display_type, default: 'text'  # text, textarea, select, multiselect, checkbox, date, number, currency, email, url, phone
      t.integer :display_order, default: 0
      t.boolean :show_in_list, default: true   # Show in list/grid views
      t.boolean :show_in_form, default: true   # Show in create/edit forms
      t.boolean :show_in_search, default: false # Include in search
      
      # Field options (for select/multiselect)
      t.jsonb :options, default: []
      # [
      #   { value: 'small', label: 'Small Business' },
      #   { value: 'medium', label: 'Medium Business' },
      #   { value: 'enterprise', label: 'Enterprise' }
      # ]
      
      # Validation rules
      t.jsonb :validations, default: {}
      # {
      #   required: true,
      #   min: 0,
      #   max: 1000000,
      #   pattern: '^[A-Z]{3}-\\d{4}$',
      #   message: 'Must be in format ABC-1234'
      # }
      
      # Default value
      t.string :default_value
      
      # For reference fields
      t.string :reference_model  # Target model for reference fields
      t.string :reference_display_field, default: 'name'  # Field to display from referenced model
      
      # Status
      t.boolean :active, default: true
      
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end

    add_index :custom_field_definitions, [:entity_id, :model_type, :field_name], unique: true, name: 'idx_custom_fields_entity_model_name'
    add_index :custom_field_definitions, [:entity_id, :model_type]
    add_index :custom_field_definitions, :field_type
    add_index :custom_field_definitions, :active
  end
end





