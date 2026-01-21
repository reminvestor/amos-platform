# frozen_string_literal: true

# HasCustomFields
#
# Concern for models that support dynamic custom fields.
# Custom fields are stored in a JSONB column and defined via CustomFieldDefinition.
#
module HasCustomFields
  extend ActiveSupport::Concern

  included do
    # Ensure custom_fields column exists
    unless column_names.include?('custom_fields')
      Rails.logger.warn "#{name} includes HasCustomFields but doesn't have custom_fields column"
    end

    # Validate custom fields against their definitions
    validate :validate_custom_fields
  end

  # ============================================
  # ACCESSORS
  # ============================================

  # Get a custom field value
  def get_custom_field(field_name)
    field_def = custom_field_definition(field_name)
    return nil unless field_def

    value = custom_fields[field_name.to_s]
    field_def.cast_value(value)
  end

  # Set a custom field value
  def set_custom_field(field_name, value)
    field_def = custom_field_definition(field_name)
    return false unless field_def

    self.custom_fields = custom_fields.merge(field_name.to_s => value)
    true
  end

  # Get all custom field values with their definitions
  def custom_field_values
    custom_field_definitions_for_model.active.map do |field_def|
      {
        field_name: field_def.field_name,
        field_label: field_def.label,
        field_type: field_def.field_type,
        value: get_custom_field(field_def.field_name),
        raw_value: custom_fields[field_def.field_name]
      }
    end
  end

  # ============================================
  # HELPERS
  # ============================================

  # Get custom field definitions for this model type
  def custom_field_definitions_for_model
    return CustomFieldDefinition.none unless respond_to?(:entity_id) && entity_id.present?

    CustomFieldDefinition.where(
      entity_id: entity_id,
      model_type: self.class.name
    )
  end

  # Get a specific field definition
  def custom_field_definition(field_name)
    custom_field_definitions_for_model.find_by(field_name: field_name.to_s)
  end

  # Get custom field definitions for list display
  def list_custom_fields
    custom_field_definitions_for_model.active.for_list.map do |field_def|
      {
        field_name: field_def.field_name,
        field_label: field_def.label,
        value: get_custom_field(field_def.field_name)
      }
    end
  end

  # Get custom field definitions for form display
  def form_custom_fields
    custom_field_definitions_for_model.active.for_form.map do |field_def|
      {
        field_name: field_def.field_name,
        field_label: field_def.label,
        field_type: field_def.field_type,
        display_type: field_def.display_type,
        value: get_custom_field(field_def.field_name),
        required: field_def.required?,
        options: field_def.options_for_select,
        help_text: field_def.help_text,
        input_attributes: field_def.input_attributes
      }
    end
  end

  # ============================================
  # SEARCHING
  # ============================================

  # Scope for searching custom fields (requires GIN index on custom_fields column)
  class_methods do
    def with_custom_field(field_name, value)
      where("custom_fields @> ?", { field_name.to_s => value }.to_json)
    end

    def with_custom_field_containing(field_name, value)
      where("custom_fields ->> ? ILIKE ?", field_name.to_s, "%#{value}%")
    end
  end

  private

  # Validate custom fields
  def validate_custom_fields
    return unless custom_fields.present?
    return unless respond_to?(:entity_id) && entity_id.present?

    custom_field_definitions_for_model.active.each do |field_def|
      value = custom_fields[field_def.field_name]
      
      errors_for_field = field_def.validate_value(value)
      errors_for_field.each do |error_message|
        errors.add(:custom_fields, error_message)
      end
    end
  end
end





