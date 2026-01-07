# frozen_string_literal: true

# DynamicModelLoader
#
# Loads AI-generated model classes at runtime from ModuleCode records.
# Creates virtual tables and Active Record models that can be queried
# like regular Rails models.
#
# SECURITY: This executes AI-generated code. All code must be validated
# and sandboxed before execution.
#
module Modules
  class DynamicModelLoader
    include Singleton

    # Cache of loaded model classes
    attr_reader :loaded_models

    def initialize
      @loaded_models = {}
      @mutex = Mutex.new
    end

    # Load all deployed module models for an entity
    def load_entity_modules(entity)
      entity.app_modules.deployed.each do |app_module|
        load_module_models(app_module)
      end
    end

    # Load all models for a specific module
    def load_module_models(app_module)
      app_module.module_codes.models.validated_or_deployed.each do |model_code|
        load_model(model_code)
      end
    end

    # Load a single model from ModuleCode
    def load_model(model_code)
      @mutex.synchronize do
        return @loaded_models[model_code.id] if @loaded_models[model_code.id]

        begin
          # Ensure table exists
          ensure_table_exists(model_code)

          # Create the model class
          model_class = create_model_class(model_code)

          # Store reference
          @loaded_models[model_code.id] = model_class
          model_code.mark_loaded!

          Rails.logger.info "[DynamicModelLoader] Loaded model: #{model_code.name} for module #{model_code.app_module.slug}"

          model_class
        rescue => e
          Rails.logger.error "[DynamicModelLoader] Failed to load #{model_code.name}: #{e.message}"
          model_code.mark_failed!("Load error: #{e.message}")
          nil
        end
      end
    end

    # Unload a model
    def unload_model(model_code)
      @mutex.synchronize do
        model_class = @loaded_models.delete(model_code.id)
        
        if model_class
          # Remove the constant if it was defined
          namespace = model_namespace(model_code.app_module)
          if namespace.const_defined?(model_code.name)
            namespace.send(:remove_const, model_code.name)
          end
          
          model_code.mark_unloaded!
          Rails.logger.info "[DynamicModelLoader] Unloaded model: #{model_code.name}"
        end
      end
    end

    # Reload a model (for updates)
    def reload_model(model_code)
      unload_model(model_code)
      load_model(model_code)
    end

    # Clear all cached models for a module (used during retry/fix cycles)
    def clear_module_cache(app_module)
      @mutex.synchronize do
        app_module.module_codes.models.each do |model_code|
          model_class = @loaded_models.delete(model_code.id)
          
          if model_class
            # Remove the constant if it was defined
            namespace = model_namespace(app_module)
            if namespace.const_defined?(model_code.name, false)
              namespace.send(:remove_const, model_code.name)
            end
            
            model_code.update_column(:status, 'pending')
          end
        end
        
        Rails.logger.info "[DynamicModelLoader] Cleared cache for module: #{app_module.slug}"
      end
    end

    # Get a loaded model class by module and name
    def get_model(app_module, model_name)
      model_code = app_module.module_codes.models.find_by(name: model_name)
      return nil unless model_code

      @loaded_models[model_code.id] || load_model(model_code)
    end

    # Get model by full path (e.g., "inventory/Product")
    def get_model_by_path(entity, path)
      module_slug, model_name = path.split('/')
      app_module = entity.app_modules.find_by(slug: module_slug)
      return nil unless app_module

      get_model(app_module, model_name)
    end

    # List all loaded models for an entity
    def list_models(entity)
      entity.app_modules.flat_map do |app_module|
        app_module.module_codes.models.currently_loaded.map do |model_code|
          {
            module_slug: app_module.slug,
            model_name: model_code.name,
            table_name: model_code.table_name,
            loaded_at: model_code.last_loaded_at
          }
        end
      end
    end

    private

    # Create the table if it doesn't exist
    def ensure_table_exists(model_code)
      schema = model_code.schema_definition.deep_symbolize_keys
      table_name = schema[:table_name] || model_code.name.underscore.pluralize
      
      return if ActiveRecord::Base.connection.table_exists?(table_name)

      Rails.logger.info "[DynamicModelLoader] Creating table: #{table_name}"

      # Collect belongs_to associations with their FK column names
      # We'll add these columns manually to handle custom foreign_key names
      belongs_to_associations = []
      association_fk_columns = Set.new(['entity_id']) # entity is always added
      
      (schema[:associations] || []).each do |assoc|
        next unless assoc.is_a?(Hash)
        next unless assoc[:type].to_s == 'belongs_to'
        next unless assoc[:model].present?
        
        target = assoc[:model].to_s.underscore
        next if target.blank?
        
        # Use custom foreign_key if specified, otherwise derive from model name
        fk_name = if assoc[:foreign_key].present?
                    assoc[:foreign_key].to_s
                  else
                    "#{target}_id"
                  end
        
        association_fk_columns << fk_name
        
        # Skip entity - handled separately
        next if target == 'entity'
        
        belongs_to_associations << {
          target: target,
          fk_column: fk_name,
          optional: assoc[:optional] != false
        }
      end

      ActiveRecord::Base.connection.create_table(table_name) do |t|
        # Always add entity reference for multi-tenancy
        t.references :entity, null: false, foreign_key: true

        # Add defined fields (skip system fields and FK columns from associations)
        # Support both :fields and :columns keys for backwards compatibility
        system_fields = %w[id created_at updated_at]
        field_definitions = schema[:fields] || schema[:columns] || []
        
        field_definitions.each do |field|
          next unless field.is_a?(Hash) && field[:name].present?
          field_name = field[:name].to_s
          next if field_name.blank?
          next if system_fields.include?(field_name)
          next if field[:primary] # Skip primary key columns
          next if association_fk_columns.include?(field_name) # Skip FK columns - added by associations
          add_column_to_table(t, field)
        end

        # Add belongs_to foreign key columns manually
        # This handles custom foreign_key names (like parent_id for self-referential)
        belongs_to_associations.each do |assoc|
          t.bigint assoc[:fk_column].to_sym, null: assoc[:optional]
        end

        t.timestamps
      end

      # Add indexes (skip if already exists)
      (schema[:indexes] || []).each do |index|
        next unless index.is_a?(Hash) && index[:fields].present?
        
        raw_fields = Array(index[:fields]).compact.map { |f| f.to_s.to_sym }.reject { |f| f.blank? || f == :"" }
        next if raw_fields.empty?
        
        unique = index[:unique] == true
        
        # Check if index already exists (references creates indexes automatically)
        begin
          unless ActiveRecord::Base.connection.index_exists?(table_name, raw_fields)
            ActiveRecord::Base.connection.add_index(table_name, raw_fields, unique: unique)
          end
        rescue => e
          Rails.logger.warn "[DynamicModelLoader] Index creation skipped: #{e.message}"
        end
      end
    end

    def add_column_to_table(t, field)
      name = field[:name].to_sym
      raw_type = field[:type] || field[:field_type] || 'string'
      raw_type = raw_type.to_s
      
      # Skip if no valid name
      return if name.blank?
      
      # Map common type aliases to Rails column types
      type = case raw_type.downcase
             when 'bigint' then :bigint
             when 'int', 'integer' then :integer
             when 'string', 'varchar' then :string
             when 'text' then :text
             when 'boolean', 'bool' then :boolean
             when 'decimal', 'numeric' then :decimal
             when 'float', 'double' then :float
             when 'date' then :date
             when 'datetime', 'timestamp' then :datetime
             when 'time' then :time
             when 'json', 'jsonb' then :jsonb
             when 'uuid' then :uuid
             when 'binary', 'blob' then :binary
             else raw_type.to_sym
             end
      
      options = {}

      options[:null] = field[:null] if field.key?(:null)
      options[:default] = field[:default] if field.key?(:default)
      options[:precision] = field[:precision] if field[:precision]
      options[:scale] = field[:scale] if field[:scale]
      options[:limit] = field[:limit] if field[:limit]
      options[:array] = field[:array] if field[:array]

      t.send(type, name, **options)
    end

    # Create the model class dynamically
    def create_model_class(model_code)
      schema = model_code.schema_definition.deep_symbolize_keys
      table_name = schema[:table_name] || model_code.name.underscore.pluralize
      namespace = model_namespace(model_code.app_module)

      # Build the class
      model_class = Class.new(ApplicationRecord) do
        self.table_name = table_name

        # Always belong to entity for multi-tenancy
        belongs_to :entity
      end

      # Add associations
      add_associations(model_class, schema[:associations] || [])

      # Add validations
      add_validations(model_class, schema[:validations] || [])

      # Add scopes
      add_scopes(model_class, schema[:scopes] || [])

      # Set the constant name
      const_name = model_code.name.to_sym
      namespace.const_set(const_name, model_class)

      model_class
    end

    def model_namespace(app_module)
      module_name = app_module.slug.camelize.to_sym

      # Create Modules namespace if needed
      unless Object.const_defined?(:Modules)
        Object.const_set(:Modules, Module.new)
      end

      # Create module-specific namespace if needed
      unless Modules.const_defined?(module_name)
        Modules.const_set(module_name, Module.new)
      end

      "Modules::#{module_name}".constantize
    end

    def add_associations(model_class, associations)
      associations.each do |assoc|
        next unless assoc[:type].present? && assoc[:model].present?
        
        type = assoc[:type].to_s.to_sym
        target = assoc[:model].to_s.underscore.to_sym
        
        # Skip empty targets
        next if target.blank? || target == :""
        
        # Skip entity - already defined in create_model_class for multi-tenancy
        next if target == :entity && type == :belongs_to
        
        options = {}

        options[:optional] = assoc[:optional] if assoc.key?(:optional)
        options[:class_name] = assoc[:class_name].to_s if assoc[:class_name].present?
        options[:foreign_key] = assoc[:foreign_key].to_s if assoc[:foreign_key].present?
        options[:dependent] = assoc[:dependent].to_s.to_sym if assoc[:dependent].present?

        begin
          case type
          when :belongs_to
            model_class.belongs_to(target, **options)
          when :has_many
            model_class.has_many(target, **options)
          when :has_one
            model_class.has_one(target, **options)
          end
        rescue => e
          Rails.logger.warn "[DynamicModelLoader] Failed to add association #{type} #{target}: #{e.message}"
        end
      end
    end

    def add_validations(model_class, validations)
      validations.each do |val|
        next unless val[:type].present?
        
        type = val[:type].to_s.to_sym
        
        begin
          case type
          when :presence
            raw_fields = val[:fields] || val[:field]
            next if raw_fields.blank?
            fields = Array(raw_fields).compact.map { |f| f.to_s.to_sym }.reject { |f| f.blank? || f == :"" }
            next if fields.empty?
            model_class.validates(*fields, presence: true)
          when :uniqueness
            next unless val[:field].present?
            field = val[:field].to_s.to_sym
            scope = val[:scope].present? ? val[:scope].to_s.to_sym : :entity_id
            model_class.validates(field, uniqueness: { scope: scope })
          when :numericality
            next unless val[:field].present?
            field = val[:field].to_s.to_sym
            opts = (val[:options] || {}).transform_keys { |k| k.to_s.to_sym }
            model_class.validates(field, numericality: opts)
          when :inclusion
            next unless val[:field].present?
            field = val[:field].to_s.to_sym
            values = Array(val[:in] || val[:options]&.dig(:in) || val[:options]&.dig('in'))
            next if values.empty?
            model_class.validates(field, inclusion: { in: values })
          when :length
            next unless val[:field].present?
            field = val[:field].to_s.to_sym
            opts = (val[:options] || {}).transform_keys { |k| k.to_s.to_sym }
            model_class.validates(field, length: opts)
          when :format
            next unless val[:field].present?
            field = val[:field].to_s.to_sym
            
            # Get pattern from :pattern or :options[:with]
            raw_pattern = val[:pattern] || val.dig(:options, :with) || val.dig(:options, 'with')
            next unless raw_pattern.present?
            
            # Handle special Ruby constants like URI::MailTo::EMAIL_REGEXP
            pattern_str = raw_pattern.to_s
            if pattern_str.include?('::')
              # Skip Ruby constant references - use a simple fallback
              Rails.logger.warn "[DynamicModelLoader] Skipping format validation with Ruby constant: #{pattern_str}"
              next
            end
            
            begin
              pattern = Regexp.new(pattern_str)
            rescue RegexpError => e
              Rails.logger.warn "[DynamicModelLoader] Invalid regex pattern '#{pattern_str}': #{e.message}"
              next
            end
            
            opts = { with: pattern }
            opts[:allow_blank] = true if val.dig(:options, :allow_blank) || val.dig(:options, 'allow_blank')
            opts[:message] = val[:message].to_s if val[:message].present?
            model_class.validates(field, format: opts)
          end
        rescue => e
          Rails.logger.warn "[DynamicModelLoader] Failed to add validation #{type}: #{e.message}"
        end
      end
    end

    def add_scopes(model_class, scopes)
      scopes.each do |scope_def|
        name = scope_def[:name].to_sym
        condition = scope_def[:condition].to_s
        
        begin
          # Parse simple scope conditions
          # For security, we only support simple declarative scopes
          
          # Handle hash-style where: where(status: 'active') or where(status: ['a', 'b'])
          if condition.match?(/\Awhere\(\s*(\w+):\s*(.+)\s*\)\z/)
            match = condition.match(/\Awhere\(\s*(\w+):\s*(.+)\s*\)\z/)
            field = match[1].to_sym
            value_str = match[2].strip
            
            # Parse the value safely
            value = case value_str
                    when /\A'(.*)'\z/ then $1  # Single quoted string
                    when /\A"(.*)"\z/ then $1  # Double quoted string
                    when 'true' then true
                    when 'false' then false
                    when 'nil' then nil
                    when /\A\d+\z/ then value_str.to_i
                    when /\A\d+\.\d+\z/ then value_str.to_f
                    when /\A\[.*\]\z/
                      # Array like ['a', 'b'] - parse safely
                      value_str.gsub(/[\[\]]/, '').split(',').map(&:strip).map { |v| v.gsub(/['"]/, '') }
                    else
                      Rails.logger.warn "[DynamicModelLoader] Unsupported scope value: #{value_str}"
                      next
                    end
            
            model_class.scope(name, -> { where(field => value) })
            
          # Handle order: order(created_at: :desc)
          elsif condition.match?(/\Aorder\(\s*(\w+):\s*:?(\w+)\s*\)\z/)
            match = condition.match(/\Aorder\(\s*(\w+):\s*:?(\w+)\s*\)\z/)
            field = match[1].to_sym
            direction = match[2].to_sym
            model_class.scope(name, -> { order(field => direction) })
            
          else
            # Skip complex SQL conditions - they're not safe to eval
            Rails.logger.warn "[DynamicModelLoader] Skipping complex scope #{name}: #{condition}"
          end
        rescue => e
          Rails.logger.warn "[DynamicModelLoader] Failed to create scope #{name}: #{e.message}"
        end
      end
    end
  end
end

