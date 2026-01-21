# frozen_string_literal: true

# == Schema Information
#
# Table name: custom_field_definitions
#
#  id                      :bigint           not null, primary key
#  entity_id               :bigint           not null
#  app_module_id           :bigint
#  model_type              :string           not null
#  field_name              :string           not null
#  field_type              :string           not null
#  field_label             :string
#  field_description       :text
#  display_type            :string           default("text")
#  display_order           :integer          default(0)
#  show_in_list            :boolean          default(true)
#  show_in_form            :boolean          default(true)
#  show_in_search          :boolean          default(false)
#  options                 :jsonb            default([])
#  validations             :jsonb            default({})
#  default_value           :string
#  reference_model         :string
#  reference_display_field :string           default("name")
#  active                  :boolean          default(true)
#  metadata                :jsonb            default({})
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
class CustomFieldDefinition < ApplicationRecord
  # Associations
  belongs_to :entity
  belongs_to :app_module, optional: true

  # Field types
  FIELD_TYPES = %w[string text integer decimal boolean date datetime json array reference].freeze
  
  # Display types
  DISPLAY_TYPES = %w[text textarea number currency email url phone select multiselect checkbox radio date datetime color file].freeze

  # Models that support custom fields
  SUPPORTED_MODELS = %w[Contact Campaign LandingPage Opportunity].freeze

  # Validations
  validates :model_type, presence: true
  validates :field_name, presence: true, 
            uniqueness: { scope: [:entity_id, :model_type] },
            format: { with: /\A[a-z][a-z0-9_]*\z/, message: 'must be lowercase with underscores' }
  validates :field_type, presence: true, inclusion: { in: FIELD_TYPES }
  validates :display_type, inclusion: { in: DISPLAY_TYPES }
  validates :reference_model, presence: true, if: -> { field_type == 'reference' }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :for_model, ->(model) { where(model_type: model) }
  scope :for_list, -> { where(show_in_list: true).order(:display_order) }
  scope :for_form, -> { where(show_in_form: true).order(:display_order) }
  scope :searchable, -> { where(show_in_search: true) }
  scope :ordered, -> { order(:display_order, :field_name) }

  # Callbacks
  before_validation :set_defaults
  before_validation :sanitize_field_name

  # ============================================
  # FIELD METADATA
  # ============================================

  def label
    field_label.presence || field_name.titleize
  end

  def placeholder
    metadata['placeholder'] || "Enter #{label.downcase}"
  end

  def help_text
    field_description
  end

  # ============================================
  # VALIDATION HELPERS
  # ============================================

  def required?
    validations['required'] == true
  end

  def min_value
    validations['min']
  end

  def max_value
    validations['max']
  end

  def min_length
    validations['min_length']
  end

  def max_length
    validations['max_length']
  end

  def pattern
    validations['pattern']
  end

  def validation_message
    validations['message']
  end

  # Validate a value against this field's rules
  def validate_value(value)
    errors = []
    
    if required? && value.blank?
      errors << (validation_message || "#{label} is required")
    end
    
    return errors if value.blank?
    
    case field_type
    when 'integer', 'decimal'
      errors << "#{label} must be a number" unless value.to_s.match?(/\A-?\d+\.?\d*\z/)
      errors << "#{label} must be at least #{min_value}" if min_value && value.to_f < min_value
      errors << "#{label} must be at most #{max_value}" if max_value && value.to_f > max_value
    when 'string', 'text'
      errors << "#{label} must be at least #{min_length} characters" if min_length && value.length < min_length
      errors << "#{label} must be at most #{max_length} characters" if max_length && value.length > max_length
      errors << (validation_message || "#{label} format is invalid") if pattern && !value.match?(Regexp.new(pattern))
    when 'date', 'datetime'
      begin
        Date.parse(value.to_s)
      rescue ArgumentError
        errors << "#{label} must be a valid date"
      end
    end
    
    errors
  end

  # ============================================
  # OPTIONS HELPERS (for select fields)
  # ============================================

  def option_values
    options.map { |o| o['value'] }
  end

  def option_labels
    options.map { |o| o['label'] || o['value'] }
  end

  def options_for_select
    options.map { |o| [o['label'] || o['value'], o['value']] }
  end

  def add_option(value, label = nil)
    new_option = { 'value' => value, 'label' => label || value }
    self.options = options + [new_option]
  end

  def remove_option(value)
    self.options = options.reject { |o| o['value'] == value }
  end

  # ============================================
  # FORM RENDERING HELPERS
  # ============================================

  def input_attributes
    attrs = {
      name: "custom_fields[#{field_name}]",
      id: "custom_field_#{field_name}",
      placeholder: placeholder,
      required: required?
    }
    
    case field_type
    when 'integer'
      attrs[:type] = 'number'
      attrs[:step] = 1
      attrs[:min] = min_value if min_value
      attrs[:max] = max_value if max_value
    when 'decimal'
      attrs[:type] = 'number'
      attrs[:step] = 'any'
      attrs[:min] = min_value if min_value
      attrs[:max] = max_value if max_value
    when 'text'
      attrs[:rows] = metadata['rows'] || 4
    when 'string'
      attrs[:type] = display_type_to_input_type
      attrs[:pattern] = pattern if pattern
      attrs[:maxlength] = max_length if max_length
    end
    
    attrs
  end

  def display_type_to_input_type
    case display_type
    when 'email' then 'email'
    when 'url' then 'url'
    when 'phone' then 'tel'
    when 'number', 'currency' then 'number'
    when 'date' then 'date'
    when 'datetime' then 'datetime-local'
    when 'color' then 'color'
    else 'text'
    end
  end

  # ============================================
  # VALUE CASTING
  # ============================================

  def cast_value(value)
    return default_value_casted if value.nil? && default_value.present?
    return nil if value.nil?
    
    case field_type
    when 'integer' then value.to_i
    when 'decimal' then value.to_f
    when 'boolean' then ActiveModel::Type::Boolean.new.cast(value)
    when 'date' then Date.parse(value.to_s) rescue nil
    when 'datetime' then DateTime.parse(value.to_s) rescue nil
    when 'json' then value.is_a?(String) ? JSON.parse(value) : value
    when 'array' then Array(value)
    else value.to_s
    end
  end

  def default_value_casted
    cast_value(default_value)
  end

  private

  def set_defaults
    self.field_label ||= field_name&.titleize
    self.display_type ||= infer_display_type
  end

  def sanitize_field_name
    self.field_name = field_name&.downcase&.gsub(/[^a-z0-9_]/, '_')&.gsub(/_+/, '_')&.gsub(/^_|_$/, '')
  end

  def infer_display_type
    case field_type
    when 'text' then 'textarea'
    when 'integer', 'decimal' then 'number'
    when 'boolean' then 'checkbox'
    when 'date' then 'date'
    when 'datetime' then 'datetime'
    when 'array' then 'multiselect'
    else 'text'
    end
  end
end





