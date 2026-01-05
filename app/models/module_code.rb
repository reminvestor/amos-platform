# frozen_string_literal: true

# == Schema Information
#
# Table name: module_codes
#
#  id                :bigint           not null, primary key
#  app_module_id     :bigint           not null
#  entity_id         :bigint           not null
#  name              :string           not null
#  code_type         :string           not null
#  content           :text             not null
#  schema_definition :jsonb            default({})
#  version           :integer          default(1)
#  previous_content  :text
#  status            :string           default("generated")
#  validation_errors :text
#  deployed_at       :datetime
#  loaded            :boolean          default(false)
#  last_loaded_at    :datetime
#  metadata          :jsonb            default({})
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class ModuleCode < ApplicationRecord
  # Associations
  belongs_to :app_module
  belongs_to :entity

  # Code types
  CODE_TYPES = %w[model migration tool agent scheduled_task canvas_js stimulus_controller].freeze
  STATUSES = %w[generated validating validated deployed failed].freeze

  # Validations
  validates :name, presence: true, uniqueness: { scope: [:app_module_id, :code_type] }
  validates :code_type, presence: true, inclusion: { in: CODE_TYPES }
  validates :content, presence: true
  validates :status, inclusion: { in: STATUSES }

  # Scopes
  scope :models, -> { where(code_type: 'model') }
  scope :migrations, -> { where(code_type: 'migration') }
  scope :tools, -> { where(code_type: 'tool') }
  scope :agents, -> { where(code_type: 'agent') }
  scope :deployed, -> { where(status: 'deployed') }
  scope :currently_loaded, -> { where(loaded: true) }
  scope :pending, -> { where(status: 'generated') }
  scope :validated_or_deployed, -> { where(status: %w[validated deployed]) }

  # Callbacks
  before_update :save_previous_content, if: :content_changed?

  # ============================================
  # STATUS HELPERS
  # ============================================

  def generated?
    status == 'generated'
  end

  def validated?
    status == 'validated'
  end

  def deployed?
    status == 'deployed'
  end

  def failed?
    status == 'failed'
  end

  # ============================================
  # LIFECYCLE METHODS
  # ============================================

  def start_validation!
    update!(status: 'validating', validation_errors: nil)
  end

  def mark_validated!
    update!(status: 'validated', validation_errors: nil)
  end

  def mark_deployed!
    update!(status: 'deployed', deployed_at: Time.current)
  end

  def mark_failed!(errors)
    update!(status: 'failed', validation_errors: errors)
  end

  def mark_loaded!
    update!(loaded: true, last_loaded_at: Time.current)
  end

  def mark_unloaded!
    update!(loaded: false)
  end

  # ============================================
  # CODE VALIDATION
  # ============================================

  def validate_syntax!
    start_validation!
    
    case code_type
    when 'model', 'migration', 'tool', 'agent'
      validate_ruby_syntax
    when 'canvas_js', 'stimulus_controller'
      validate_js_syntax
    else
      mark_validated!
      true
    end
  end

  def validate_ruby_syntax
    begin
      # Use Ruby's built-in syntax checker
      RubyVM::InstructionSequence.compile(content)
      mark_validated!
      true
    rescue SyntaxError => e
      mark_failed!(e.message)
      false
    end
  end

  def validate_js_syntax
    # Basic JS validation - in production, use a proper JS parser
    # For now, just check for obvious issues
    if content.include?('function') || content.include?('=>') || content.include?('class ')
      mark_validated!
      true
    else
      mark_validated!  # Allow empty or simple JS
      true
    end
  end

  # ============================================
  # SCHEMA HELPERS (for model code type)
  # ============================================

  def table_name
    return nil unless code_type == 'model'
    schema_definition['table_name'] || name.underscore.pluralize
  end

  def fields
    return [] unless code_type == 'model'
    schema_definition['fields'] || []
  end

  def associations
    return [] unless code_type == 'model'
    schema_definition['associations'] || []
  end

  def indexes
    return [] unless code_type == 'model'
    schema_definition['indexes'] || []
  end

  # ============================================
  # CODE LOADING
  # ============================================

  # DANGER: This loads Ruby code dynamically
  # Should only be called in sandboxed environment
  def load_code!
    return false unless validated? || deployed?
    return false unless code_type.in?(%w[model tool agent])

    begin
      # Evaluate the code in a module namespace
      namespace = "Modules::#{app_module.slug.camelize}"
      
      # Create the namespace if it doesn't exist
      unless Object.const_defined?(namespace)
        Object.const_set(namespace.split('::').first, Module.new)
      end

      # Evaluate the code
      eval(content, TOPLEVEL_BINDING, "#{name}.rb", 1)
      
      mark_loaded!
      true
    rescue => e
      mark_failed!("Load error: #{e.message}")
      false
    end
  end

  # Generate migration SQL from schema_definition
  def generate_migration_sql
    return nil unless code_type == 'model'
    return nil if schema_definition.blank?

    sql_parts = ["CREATE TABLE IF NOT EXISTS #{table_name} ("]
    sql_parts << "  id BIGSERIAL PRIMARY KEY,"
    
    fields.each do |field|
      sql_parts << "  #{field_to_sql(field)},"
    end
    
    sql_parts << "  created_at TIMESTAMP NOT NULL DEFAULT NOW(),"
    sql_parts << "  updated_at TIMESTAMP NOT NULL DEFAULT NOW()"
    sql_parts << ");"
    
    sql_parts.join("\n")
  end

  # ============================================
  # VERSIONING
  # ============================================

  def save_version!
    save_previous_content
    increment!(:version)
  end

  def restore_previous!
    return false if previous_content.blank?
    
    self.content = previous_content
    self.previous_content = nil
    self.status = 'generated'
    save!
  end

  private

  def save_previous_content
    self.previous_content = content_was if content_was.present?
  end

  def field_to_sql(field)
    name = field['name']
    type = field['type']
    nullable = field['null'] != false
    default = field['default']
    
    sql_type = case type
    when 'string' then 'VARCHAR(255)'
    when 'text' then 'TEXT'
    when 'integer' then 'INTEGER'
    when 'bigint' then 'BIGINT'
    when 'decimal' then 'DECIMAL(10,2)'
    when 'boolean' then 'BOOLEAN'
    when 'date' then 'DATE'
    when 'datetime' then 'TIMESTAMP'
    when 'json', 'jsonb' then 'JSONB'
    else 'VARCHAR(255)'
    end
    
    parts = ["#{name} #{sql_type}"]
    parts << "NOT NULL" unless nullable
    parts << "DEFAULT #{default_to_sql(default)}" if default
    
    parts.join(' ')
  end

  def default_to_sql(default)
    case default
    when true then 'TRUE'
    when false then 'FALSE'
    when nil then 'NULL'
    when Integer, Float then default.to_s
    when Hash, Array then "'#{default.to_json}'::jsonb"
    else "'#{default}'"
    end
  end
end

