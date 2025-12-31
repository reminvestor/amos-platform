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

      ActiveRecord::Base.connection.create_table(table_name) do |t|
        # Always add entity reference for multi-tenancy
        t.references :entity, null: false, foreign_key: true

        # Add defined fields
        (schema[:fields] || []).each do |field|
          add_column_to_table(t, field)
        end

        # Add associations
        (schema[:associations] || []).each do |assoc|
          if assoc[:type].to_s == 'belongs_to'
            target = assoc[:model].to_s.underscore
            t.references target.to_sym, null: assoc[:optional] != false, foreign_key: assoc[:foreign_key] != false
          end
        end

        t.timestamps
      end

      # Add indexes
      (schema[:indexes] || []).each do |index|
        fields = Array(index[:fields]).map(&:to_sym)
        unique = index[:unique] == true
        ActiveRecord::Base.connection.add_index(table_name, fields, unique: unique)
      end
    end

    def add_column_to_table(t, field)
      name = field[:name].to_sym
      type = field[:type].to_sym
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
        type = assoc[:type].to_sym
        target = assoc[:model].to_s.underscore.to_sym
        options = {}

        options[:optional] = assoc[:optional] if assoc.key?(:optional)
        options[:class_name] = assoc[:class_name] if assoc[:class_name]
        options[:foreign_key] = assoc[:foreign_key] if assoc[:foreign_key]
        options[:dependent] = assoc[:dependent].to_sym if assoc[:dependent]

        case type
        when :belongs_to
          model_class.belongs_to(target, **options)
        when :has_many
          model_class.has_many(target, **options)
        when :has_one
          model_class.has_one(target, **options)
        end
      end
    end

    def add_validations(model_class, validations)
      validations.each do |val|
        type = val[:type].to_sym
        
        case type
        when :presence
          fields = Array(val[:fields] || val[:field]).map(&:to_sym)
          model_class.validates(*fields, presence: true)
        when :uniqueness
          field = val[:field].to_sym
          scope = val[:scope] ? val[:scope].to_sym : :entity_id
          model_class.validates(field, uniqueness: { scope: scope })
        when :numericality
          field = val[:field].to_sym
          opts = (val[:options] || {}).transform_keys(&:to_sym)
          model_class.validates(field, numericality: opts)
        when :inclusion
          field = val[:field].to_sym
          values = Array(val[:in])
          model_class.validates(field, inclusion: { in: values })
        when :length
          field = val[:field].to_sym
          opts = (val[:options] || {}).transform_keys(&:to_sym)
          model_class.validates(field, length: opts)
        when :format
          field = val[:field].to_sym
          pattern = Regexp.new(val[:pattern])
          message = val[:message]
          opts = { with: pattern }
          opts[:message] = message if message
          model_class.validates(field, format: opts)
        end
      end
    end

    def add_scopes(model_class, scopes)
      scopes.each do |scope_def|
        name = scope_def[:name].to_sym
        condition = scope_def[:condition]
        
        # Parse simple scope conditions
        # For security, we only support simple declarative scopes
        if condition.match?(/\Awhere\((.*)\)\z/)
          # Extract the hash from where()
          hash_str = condition.match(/\Awhere\((.*)\)\z/)[1]
          begin
            # Parse simple hash conditions like "active: true"
            hash = eval("{ #{hash_str} }")
            model_class.scope(name, -> { where(hash) })
          rescue => e
            Rails.logger.warn "[DynamicModelLoader] Failed to create scope #{name}: #{e.message}"
          end
        elsif condition.match?(/\Aorder\((.*)\)\z/)
          order_str = condition.match(/\Aorder\((.*)\)\z/)[1]
          begin
            hash = eval("{ #{order_str} }")
            model_class.scope(name, -> { order(hash) })
          rescue => e
            Rails.logger.warn "[DynamicModelLoader] Failed to create scope #{name}: #{e.message}"
          end
        end
      end
    end
  end
end

