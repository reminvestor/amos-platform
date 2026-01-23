# frozen_string_literal: true

# WebAppModule links a WebApp to an AppModule
# Defines how the module is exposed within the web application
#
class WebAppModule < ApplicationRecord
  # Associations
  belongs_to :web_app
  belongs_to :app_module
  
  # View types for list display
  LIST_VIEW_TYPES = %w[table grid cards list].freeze
  
  # Validations
  validates :web_app_id, uniqueness: { scope: :app_module_id }
  validates :list_view_type, inclusion: { in: LIST_VIEW_TYPES }, allow_nil: true
  
  # Scopes
  scope :public_modules, -> { where(is_public: true) }
  scope :authenticated_modules, -> { where(is_public: false) }
  scope :by_nav_order, -> { order(:nav_order) }
  
  # Delegation
  delegate :name, :slug, :description, to: :app_module, prefix: true
  delegate :entity, to: :web_app
  
  # ============================================
  # PERMISSIONS
  # ============================================
  
  def can_create?
    allow_create
  end
  
  def can_edit?
    allow_edit
  end
  
  def can_delete?
    allow_delete
  end
  
  def permissions_for_role(role_name)
    role_permissions[role_name.to_s] || default_permissions
  end
  
  def default_permissions
    {
      'read' => true,
      'create' => allow_create,
      'edit' => allow_edit,
      'delete' => allow_delete
    }
  end
  
  # ============================================
  # FIELD VISIBILITY
  # ============================================
  
  def visible_field_names
    return all_field_names if visible_fields.empty?
    visible_fields
  end
  
  def editable_field_names
    return all_field_names if editable_fields.empty?
    editable_fields
  end
  
  def all_field_names
    schema = app_module.metadata&.dig('schema', 'fields') || []
    schema.map { |f| f['name'] }
  end
  
  def field_visible?(field_name)
    visible_fields.empty? || visible_fields.include?(field_name)
  end
  
  def field_editable?(field_name)
    editable_fields.empty? || editable_fields.include?(field_name)
  end
  
  # ============================================
  # DATA ACCESS
  # ============================================
  
  def fetch_records(user: nil, limit: 50, offset: 0, filters: {})
    model_class = app_module.dynamic_model_class
    return [] unless model_class
    
    records = model_class.where(entity_id: entity.id)
    
    # Apply filters
    filters.each do |field, value|
      records = records.where(field => value) if field_visible?(field.to_s)
    end
    
    records.limit(limit).offset(offset)
  end
  
  def fetch_record(id, user: nil)
    model_class = app_module.dynamic_model_class
    return nil unless model_class
    
    model_class.find_by(id: id, entity_id: entity.id)
  end
  
  def create_record(attributes, user: nil)
    return { error: 'Create not allowed' } unless allow_create
    
    model_class = app_module.dynamic_model_class
    return { error: 'Model not available' } unless model_class
    
    # Filter to only editable fields
    safe_attrs = attributes.slice(*editable_field_names)
    safe_attrs['entity_id'] = entity.id
    
    record = model_class.create!(safe_attrs)
    { success: true, record: record }
  rescue => e
    { error: e.message }
  end
  
  def update_record(id, attributes, user: nil)
    return { error: 'Edit not allowed' } unless allow_edit
    
    record = fetch_record(id, user: user)
    return { error: 'Record not found' } unless record
    
    # Filter to only editable fields
    safe_attrs = attributes.slice(*editable_field_names)
    
    record.update!(safe_attrs)
    { success: true, record: record }
  rescue => e
    { error: e.message }
  end
  
  def delete_record(id, user: nil)
    return { error: 'Delete not allowed' } unless allow_delete
    
    record = fetch_record(id, user: user)
    return { error: 'Record not found' } unless record
    
    record.destroy
    { success: true }
  rescue => e
    { error: e.message }
  end
  
  # ============================================
  # DISPLAY
  # ============================================
  
  def nav_icon_or_default
    nav_icon.presence || 'database'
  end
  
  def display_name
    app_module.name
  end
end

