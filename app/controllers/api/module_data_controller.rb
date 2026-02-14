# frozen_string_literal: true

# API::ModuleDataController
#
# Provides CRUD API for dynamic module models.
# Used by the module canvas controller for direct UI actions.
#
module Api
  class ModuleDataController < ApplicationController
    before_action :authenticate_user!
    before_action :set_module
    before_action :set_model, except: [:stats]
    before_action :set_record, only: [:show, :update, :destroy]

    # GET /api/modules/:module_slug/stats
    def stats
      stats = {}
      
      @app_module.module_codes.models.each do |model_code|
        model_class = load_model(model_code.name)
        next unless model_class
        
        model_name = model_code.name.underscore.pluralize
        stats[model_name] = model_class.where(entity: current_entity).count
      end

      # Add computed stats
      stats['total'] = stats.values.sum
      stats['this_week'] = calculate_this_week_count
      stats['active'] = stats['total'] # Placeholder
      stats['alerts'] = 0 # Placeholder

      render json: stats
    end

    # GET /api/modules/:module_slug/models/:model_name/schema
    def schema
      model_code = @app_module.module_codes.models.find_by(name: params[:model_name])
      
      if model_code
        schema = model_code.schema_definition.deep_symbolize_keys
        
        # Transform to frontend-friendly format
        fields = (schema[:fields] || []).reject { |f| 
          %w[id entity_id created_at updated_at].include?(f[:name].to_s) 
        }.map do |field|
          {
            name: field[:name],
            type: map_field_type(field[:type]),
            required: field[:null] == false,
            label: field[:name].to_s.humanize
          }
        end

        # Add relationship fields
        (schema[:associations] || []).each do |assoc|
          if assoc[:type].to_s == 'belongs_to' && assoc[:model].to_s != 'Entity'
            fields << {
              name: "#{assoc[:model].to_s.underscore}_id",
              type: 'select',
              required: assoc[:optional] != true,
              label: assoc[:model].to_s.humanize,
              model: assoc[:model]
            }
          end
        end

        render json: { fields: fields }
      else
        render json: { fields: [] }
      end
    end

    # GET /api/modules/:module_slug/models/:model_name
    def index
      records = @model_class.where(entity: current_entity)
      
      # Apply filters
      if params[:filter].present?
        records = apply_filter(records, params[:filter])
      end

      # Apply search
      if params[:q].present?
        records = apply_search(records, params[:q])
      end

      # Apply ordering
      order_field = params[:order_by] || 'created_at'
      order_dir = params[:order_dir] == 'asc' ? :asc : :desc
      if @model_class.column_names.include?(order_field.to_s)
        records = records.order(order_field => order_dir)
      end

      # Apply pagination
      limit = [params[:limit].to_i, 100].max
      limit = [limit, 1000].min
      offset = params[:offset].to_i

      total = records.count
      records = records.limit(limit).offset(offset)

      # Format for CSV if requested
      if params[:format] == 'csv'
        return render_csv(records)
      end

      render json: {
        success: true,
        total: total,
        limit: limit,
        offset: offset,
        records: records.map { |r| serialize_record(r) }
      }
    end

    # GET /api/modules/:module_slug/models/:model_name/:id
    def show
      render json: {
        success: true,
        record: serialize_record(@record)
      }
    end

    # POST /api/modules/:module_slug/models/:model_name
    def create
      @record = @model_class.new(permitted_params)
      @record.entity = current_entity

      if @record.save
        render json: {
          success: true,
          id: @record.id,
          record: serialize_record(@record)
        }, status: :created
      else
        render json: {
          success: false,
          message: @record.errors.full_messages.join(', '),
          errors: @record.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/modules/:module_slug/models/:model_name/:id
    def update
      if @record.update(permitted_params)
        render json: {
          success: true,
          record: serialize_record(@record)
        }
      else
        render json: {
          success: false,
          message: @record.errors.full_messages.join(', '),
          errors: @record.errors.full_messages
        }, status: :unprocessable_entity
      end
    end

    # DELETE /api/modules/:module_slug/models/:model_name/:id
    def destroy
      if @record.destroy
        render json: { success: true, message: 'Record deleted' }
      else
        render json: { success: false, message: 'Delete failed' }, status: :unprocessable_entity
      end
    end

    private

    def set_module
      @app_module = AppModule.find_by!(entity: current_entity, slug: params[:module_slug])
    rescue ActiveRecord::RecordNotFound
      render json: { error: 'Module not found' }, status: :not_found
    end

    def set_model
      @model_class = load_model(params[:model_name])
      unless @model_class
        render json: { error: 'Model not found' }, status: :not_found
      end
    end

    def set_record
      @record = @model_class.find_by(id: params[:id], entity: current_entity)
      unless @record
        render json: { error: 'Record not found' }, status: :not_found
      end
    end

    def load_model(model_name)
      # Try to get from loader
      loader = Modules::DynamicModelLoader.instance
      model_class = loader.get_model_by_path(current_entity, "#{@app_module.slug}/#{model_name}")
      
      # If not loaded, try loading module models
      unless model_class
        loader.load_module_models(@app_module)
        model_class = loader.get_model_by_path(current_entity, "#{@app_module.slug}/#{model_name}")
      end

      model_class
    end

    def permitted_params
      # Allow all columns except protected ones
      protected_columns = %w[id entity_id created_at updated_at]
      allowed_columns = @model_class.column_names - protected_columns
      
      params.permit(*allowed_columns)
    end

    def serialize_record(record)
      record.attributes.except('entity_id')
    end

    def apply_filter(records, filter)
      case filter.to_s.downcase
      when 'active'
        if @model_class.column_names.include?('active')
          records = records.where(active: true)
        end
      when 'inactive'
        if @model_class.column_names.include?('active')
          records = records.where(active: false)
        end
      when 'recent'
        records = records.where("created_at > ?", 7.days.ago)
      when 'all'
        # No filter - return all records
      else
        # Support column:value format (e.g., "city:Miami", "fish_type:Marlin")
        if filter.to_s.include?(":")
          column, value = filter.to_s.split(":", 2)
          column = column.strip.downcase
          value = value.strip
          if @model_class.column_names.include?(column) && value.present?
            records = records.where(column => value)
          end
        else
          # Try as a text search across all string/text columns
          text_columns = @model_class.columns
            .select { |c| [:string, :text].include?(c.type) }
            .map(&:name) - %w[entity_id id]

          if text_columns.any?
            conditions = text_columns.map { |col| "#{col} ILIKE ?" }.join(" OR ")
            values = text_columns.map { "%#{filter}%" }
            records = records.where(conditions, *values)
          end
        end
      end
      records
    end

    def apply_search(records, query)
      # Search across all string/text columns of the dynamic model
      searchable = @model_class.columns
        .select { |c| [:string, :text].include?(c.type) }
        .map(&:name) - %w[entity_id id]
      return records if searchable.empty?

      conditions = searchable.map { |col| "#{col} ILIKE ?" }.join(" OR ")
      values = searchable.map { "%#{query}%" }

      records.where(conditions, *values)
    end

    def calculate_this_week_count
      count = 0
      @app_module.module_codes.models.each do |model_code|
        model_class = load_model(model_code.name)
        next unless model_class
        count += model_class.where(entity: current_entity)
                           .where('created_at > ?', 1.week.ago)
                           .count
      end
      count
    end

    def render_csv(records)
      csv_data = CSV.generate(headers: true) do |csv|
        columns = @model_class.column_names - %w[entity_id]
        csv << columns
        records.each do |record|
          csv << columns.map { |col| record.send(col) }
        end
      end

      send_data csv_data, 
                filename: "#{params[:model_name].underscore}_export.csv",
                type: 'text/csv'
    end

    def map_field_type(db_type)
      case db_type.to_s.downcase
      when 'text' then 'text'
      when 'integer', 'bigint' then 'integer'
      when 'decimal', 'float', 'numeric' then 'number'
      when 'boolean' then 'boolean'
      when 'datetime', 'timestamp' then 'datetime'
      when 'date' then 'date'
      else 'string'
      end
    end

    def current_entity
      current_user.entity
    end
  end
end


