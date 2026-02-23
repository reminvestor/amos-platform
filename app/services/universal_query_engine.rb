class UniversalQueryEngine
  def initialize(user, entity)
    @user = user
    @entity = entity
  end

  def execute_get_data(params)
    # Validate parameters
    objects = Array(params[:objects])
    return { error: "No objects specified" } if objects.empty?

    # Validate all object types are queryable
    invalid_objects = objects.reject { |obj| ScoutDataRegistry.queryable?(obj) }
    return { error: "Invalid object types: #{invalid_objects.join(', ')}" } if invalid_objects.any?

    results = {}

    begin
      objects.each do |object_type|
        results[object_type] = query_object_type(object_type, params)
      end

      {
        success: true,
        data: results,
        metadata: generate_metadata(results, params)
      }
    rescue => e
      Rails.logger.error "UniversalQueryEngine error: #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Provide specific guidance for column errors
      error_message = if e.message.include?("column") && e.message.include?("does not exist")
        # Extract the problematic column name if possible
        column_match = e.message.match(/column [\"']?([^\"'\s]+)[\"']? does not exist/)
        problematic_column = column_match ? column_match[1] : "unknown column"

        "Database column '#{problematic_column}' does not exist. Use get_schema('#{params[:objects]&.first}') to discover available fields."
      elsif e.message.include?("PG::UndefinedColumn")
        "Database schema error: #{e.message}. Use get_schema() to discover the correct field names for this object type."
      else
        "Query failed: #{e.message}"
      end

      {
        success: false,
        error: error_message,
        suggestion: "Try using get_schema('#{params[:objects]&.first}') to see available fields",
        data: results  # Return partial results if any
      }
    end
  end

  private

  def query_object_type(object_type, params)
    object_config = ScoutDataRegistry.object_config(object_type)
    model_class = ScoutDataRegistry.model_class(object_type)

    # Build base query with entity scoping
    query = build_scoped_query(model_class, object_config)

    # Apply filters (pass object_type for registry lookup)
    query = apply_filters(query, params[:filters], object_config, object_type)

    # Apply ordering (default to most recent first)
    query = apply_ordering(query, params[:order_by], object_config)

    # Include relationships if requested
    query = include_relationships(query, params[:include_relationships], object_config)

    # Get true total count BEFORE applying limit
    # This ensures the AI knows the real total even when requesting limited results
    true_total_count = query.count

    # Execute query with limit
    limit = [ params[:limit] || 10, 100 ].min  # Cap at 100 for performance
    records = query.limit(limit)

    # Format results with true total
    format_records(records, object_config, params, true_total_count)
  end

  ENTITY_SHAREABLE_MODELS = %w[LandingPage EmailSequence App Website WebApp AutomationCode].freeze

  def build_scoped_query(model_class, object_config)
    # EntityShareable models use visible_to_user (user's own + shared with entity)
    if ENTITY_SHAREABLE_MODELS.include?(model_class.name) && model_class.respond_to?(:visible_to_user)
      return model_class.visible_to_user(@user)
    end

    scope_field = object_config[:scoped_by]

    case scope_field
    when "entity_id"
      model_class.where(entity_id: @entity.id)
    when "campaign.entity_id"
      model_class.joins(:campaign).where(campaigns: { entity_id: @entity.id })
    else
      if model_class.column_names.include?("entity_id")
        model_class.where(entity_id: @entity.id)
      else
        model_class.all
      end
    end
  end

  def apply_filters(query, filters, object_config, object_type = nil)
    return query unless filters.is_a?(Hash)

    # Validate and clean filters
    # Use the object_type key (e.g., "contacts") not the model class name (e.g., "Contact")
    # so ScoutDataRegistry can find the config and its queryable/filterable fields
    filter_key = object_type || object_config[:model]
    validated_filters = ScoutDataRegistry.validate_filters(filter_key, filters)

    validated_filters.each do |field, value|
      query = apply_field_filter(query, field, value)
    end

    query
  end

  def apply_field_filter(query, field, value)
    case field.to_s
    when "created_at", "updated_at", "sent_at", "scheduled_at"
      apply_date_filter(query, field, value)
    when "status"
      query.where(field => value)
    when "opted_out"
      query.where(field => [ true, false ].include?(value) ? value : false)
    else
      # Generic field filtering
      if value.is_a?(Array)
        query.where(field => value)
      else
        query.where(field => value)
      end
    end
  end

  def apply_date_filter(query, field, value)
    case value.to_s.downcase
    when "today"
      query.where(field => Date.current.all_day)
    when "yesterday"
      query.where(field => 1.day.ago.all_day)
    when "last_7_days"
      query.where(field => 7.days.ago..Time.current)
    when "last_30_days"
      query.where(field => 30.days.ago..Time.current)
    when "last_90_days"
      query.where(field => 90.days.ago..Time.current)
    when "this_month"
      query.where(field => Date.current.beginning_of_month..Date.current.end_of_month)
    when "last_month"
      last_month = 1.month.ago
      query.where(field => last_month.beginning_of_month..last_month.end_of_month)
    else
      # Try to parse as date range or specific date
      if value.is_a?(Hash) && value[:start] && value[:end]
        query.where(field => value[:start]..value[:end])
      elsif value.respond_to?(:to_date)
        query.where(field => value.to_date.all_day)
      else
        query
      end
    end
  end

  def apply_ordering(query, order_by, object_config)
    model_class = object_config[:model].constantize
    available_columns = model_class.column_names

    if order_by.present?
      # Parse order_by (e.g., "created_at desc" or "name asc")
      field, direction = order_by.to_s.split(" ")
      direction = direction&.downcase == "asc" ? :asc : :desc

      # Check if the requested field actually exists
      if available_columns.include?(field)
        query.order(field => direction)
      else
        Rails.logger.warn "Requested order field '#{field}' does not exist for #{object_config[:model]}, using safe fallback"
        safe_field = ScoutDataRegistry.get_safe_order_field(object_config[:model].underscore.pluralize)
        query.order(safe_field => direction)
      end
    else
      # Use safe default ordering
      safe_field = ScoutDataRegistry.get_safe_order_field(object_config[:model].underscore.pluralize)
      query.order(safe_field => :desc)
    end
  end

  def include_relationships(query, relationships, object_config)
    return query unless relationships.is_a?(Array)

    # Only include valid relationships
    valid_relationships = relationships & object_config[:relationships]

    if valid_relationships.any?
      query.includes(valid_relationships.map(&:to_sym))
    else
      query
    end
  end

  def format_records(records, object_config, params, true_total_count = nil)
    formatted_records = records.map do |record|
      format_single_record(record, object_config, params)
    end

    {
      records: formatted_records,
      count: formatted_records.length,
      total_available: true_total_count || estimate_total_count(records, object_config)
    }
  end

  def format_single_record(record, object_config, params)
    # Basic record data
    result = {}

    # Include queryable fields
    object_config[:queryable_fields].each do |field|
      result[field] = record.send(field) if record.respond_to?(field)
    end

    # Include metrics if requested
    if params[:include_metrics] != false
      metrics = calculate_metrics(record, object_config)
      result[:metrics] = metrics if metrics.any?
    end

    # Include relationship counts if requested
    if params[:include_relationship_counts]
      relationship_counts = calculate_relationship_counts(record, object_config)
      result[:relationship_counts] = relationship_counts if relationship_counts.any?
    end

    result
  end

  def calculate_metrics(record, object_config)
    metrics = {}

    object_config[:metrics].each do |metric|
      case metric
      when "open_rate"
        metrics[metric] = calculate_open_rate(record)
      when "click_rate"
        metrics[metric] = calculate_click_rate(record)
      when "unsubscribe_rate"
        metrics[metric] = calculate_unsubscribe_rate(record)
      when "total_sent", "total_delivered", "total_opened", "total_clicked", "total_unsubscribed"
        metrics[metric] = calculate_email_totals(record, metric)
      when "contact_count"
        metrics[metric] = record.contacts.count if record.respond_to?(:contacts)
      when "engagement_score"
        metrics[metric] = calculate_engagement_score(record)
      else
        # Try to call method directly if it exists
        if record.respond_to?(metric)
          metrics[metric] = record.send(metric)
        end
      end
    end

    metrics.compact
  end

  def calculate_relationship_counts(record, object_config)
    counts = {}

    object_config[:relationships].each do |relationship|
      if record.respond_to?(relationship)
        association = record.send(relationship)
        counts["#{relationship}_count"] = association.respond_to?(:count) ? association.count : 0
      end
    end

    counts
  end

  # Campaign-specific metric calculations
  def calculate_open_rate(record)
    return 0 unless record.respond_to?(:email_deliveries)

    total_sent = record.email_deliveries.count
    return 0 if total_sent == 0

    if EmailDelivery.column_names.include?("opened_at")
      total_opened = record.email_deliveries.where.not(opened_at: nil).count
      ((total_opened.to_f / total_sent) * 100).round(2)
    else
      0
    end
  end

  def calculate_click_rate(record)
    return 0 unless record.respond_to?(:email_deliveries)

    total_sent = record.email_deliveries.count
    return 0 if total_sent == 0

    if EmailDelivery.column_names.include?("clicked_at")
      total_clicked = record.email_deliveries.where.not(clicked_at: nil).count
      ((total_clicked.to_f / total_sent) * 100).round(2)
    else
      0
    end
  end

  def calculate_unsubscribe_rate(record)
    return 0 unless record.respond_to?(:email_deliveries)

    total_sent = record.email_deliveries.count
    return 0 if total_sent == 0

    if EmailDelivery.column_names.include?("unsubscribed_at")
      total_unsubscribed = record.email_deliveries.where.not(unsubscribed_at: nil).count
      ((total_unsubscribed.to_f / total_sent) * 100).round(2)
    else
      0
    end
  end

  def calculate_email_totals(record, metric)
    return 0 unless record.respond_to?(:email_deliveries)

    case metric
    when "total_sent"
      record.email_deliveries.count
    when "total_delivered"
      # Check if bounced_at column exists before using it
      if EmailDelivery.column_names.include?("bounced_at")
        record.email_deliveries.where(bounced_at: nil).count
      else
        # Fallback: use sent deliveries as delivered count
        record.email_deliveries.where.not(sent_at: nil).count
      end
    when "total_opened"
      if EmailDelivery.column_names.include?("opened_at")
        record.email_deliveries.where.not(opened_at: nil).count
      else
        0
      end
    when "total_clicked"
      if EmailDelivery.column_names.include?("clicked_at")
        record.email_deliveries.where.not(clicked_at: nil).count
      else
        0
      end
    when "total_unsubscribed"
      if EmailDelivery.column_names.include?("unsubscribed_at")
        record.email_deliveries.where.not(unsubscribed_at: nil).count
      else
        0
      end
    else
      0
    end
  end

  def calculate_engagement_score(record)
    # Simple engagement score calculation
    # This could be made more sophisticated based on business logic
    if record.respond_to?(:email_deliveries)
      deliveries = record.email_deliveries
      return 0 if deliveries.count == 0

      opened = deliveries.where.not(opened_at: nil).count
      clicked = deliveries.where.not(clicked_at: nil).count

      # Weight clicks higher than opens
      score = (opened * 1 + clicked * 3).to_f / deliveries.count
      (score * 10).round(1)  # Scale to 0-30 range
    else
      0
    end
  end

  def estimate_total_count(records, object_config)
    # Simple estimation - in production might want more sophisticated counting
    # For now, just return the actual count of the limited result set
    # This could be enhanced to do a separate count query for better UX
    records.respond_to?(:count) ? records.count : records.length
  end

  def generate_metadata(results, params)
    {
      query_time: Time.current,
      objects_queried: params[:objects],
      filters_applied: params[:filters] || {},
      total_records: results.values.sum { |obj| obj[:count] || 0 },
      includes_metrics: params[:include_metrics] != false
    }
  end
end
