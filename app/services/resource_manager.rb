require "concurrent"

class ResourceManager
  attr_reader :entity, :limits, :usage, :cost_tracker

  def initialize(entity)
    @entity = entity
    @limits = load_resource_limits
    @usage = Concurrent::Hash.new { |h, k| h[k] = Concurrent::AtomicFixnum.new(0) }
    @cost_tracker = CostTracker.new(entity)
    @token_tracker = TokenTracker.new(entity)
    @reservations = Concurrent::Hash.new
    @lock = Concurrent::ReadWriteLock.new

    # Start monitoring thread
    start_monitoring
  end

  # Check if resources are limited
  def limited_resources?
    @limits[:concurrent_workflows] < 5 ||
    @limits[:daily_api_calls] < 10000 ||
    @limits[:memory_mb] < 2048
  end

  # Reserve resources for an operation
  def reserve_resources(requirements)
    @lock.with_write_lock do
      # Check if resources are available
      return false unless can_allocate?(requirements)

      # Create reservation
      reservation_id = SecureRandom.uuid
      @reservations[reservation_id] = {
        requirements: requirements,
        reserved_at: Time.current,
        expires_at: Time.current + 5.minutes
      }

      # Update usage
      allocate_resources(requirements)

      reservation_id
    end
  end

  # Release reserved resources
  def release_resources(reservation_id)
    @lock.with_write_lock do
      reservation = @reservations.delete(reservation_id)
      return false unless reservation

      # Free up resources
      deallocate_resources(reservation[:requirements])

      true
    end
  end

  # Track resource usage for a block
  def track_usage(resource_type, amount = 1)
    start_time = Time.current

    # Track the usage
    @usage[resource_type].increment(amount)

    # Track cost if applicable
    if cost = calculate_cost(resource_type, amount)
      @cost_tracker.record_cost(resource_type, cost)
    end

    result = yield if block_given?

    # Record duration
    duration = Time.current - start_time
    record_usage_metrics(resource_type, amount, duration)

    result
  ensure
    # Some resources are released after use
    if [ :memory_mb, :cpu_threads ].include?(resource_type)
      @usage[resource_type].decrement(amount)
    end
  end

  # Get current usage statistics
  def usage_stats
    stats = {}

    @usage.each do |resource, atomic_value|
      stats[resource] = {
        current: atomic_value.value,
        limit: @limits[resource],
        percentage: calculate_usage_percentage(resource, atomic_value.value)
      }
    end

    stats
  end

  # Check if a specific resource is available
  def resource_available?(resource_type, amount = 1)
    current = @usage[resource_type].value
    limit = @limits[resource_type]

    return true unless limit # No limit set

    current + amount <= limit
  end

  # Track token usage for a user
  def track_tokens(user, model, tokens, context = {})
    # Track at user level
    @token_tracker.track_user_tokens(user, model, tokens, context)

    # Track at entity level
    @token_tracker.track_entity_tokens(model, tokens, context)

    # Update usage counter
    total_tokens = (tokens[:input] || 0) + (tokens[:output] || 0)
    @usage[:ai_tokens].increment(total_tokens)

    # Calculate and track cost
    cost = estimate_ai_cost(model, tokens)
    @cost_tracker.record_cost(:ai_tokens, cost, user: user)

    # Check limits
    check_token_limits(user)
  end

  # Get token usage statistics
  def token_usage_stats(user: nil, time_range: 24.hours)
    if user
      @token_tracker.get_user_stats(user, time_range)
    else
      @token_tracker.get_entity_stats(time_range)
    end
  end

  # Get detailed token breakdown
  def token_breakdown(user: nil, group_by: :model, time_range: 24.hours)
    @token_tracker.get_breakdown(
      user: user,
      group_by: group_by,
      time_range: time_range
    )
  end

  # Get cost estimate for an operation
  def estimate_cost(operations)
    total_cost = 0.0

    operations.each do |op|
      if op[:type] == :ai_call
        total_cost += estimate_ai_cost(op[:model], op[:tokens])
      elsif op[:type] == :api_call
        total_cost += estimate_api_cost(op[:service])
      elsif op[:type] == :storage
        total_cost += estimate_storage_cost(op[:size_mb])
      end
    end

    {
      estimated_cost: total_cost,
      cost_breakdown: breakdown_costs(operations),
      monthly_projection: total_cost * 30
    }
  end

  # Apply rate limiting
  def check_rate_limit(resource_type, window = 1.minute)
    key = "rate_limit:#{@entity.id}:#{resource_type}"
    current_count = Rails.cache.read(key) || 0
    limit = rate_limits[resource_type]

    return true unless limit

    if current_count >= limit
      {
        allowed: false,
        retry_after: window.to_i,
        current: current_count,
        limit: limit
      }
    else
      Rails.cache.increment(key, 1, expires_in: window)
      {
        allowed: true,
        current: current_count + 1,
        limit: limit
      }
    end
  end

  private

  def check_token_limits(user)
    # Check user daily limit
    user_daily = @token_tracker.get_user_daily_total(user)
    # Get limit from entity settings or use default
    user_limit = user.entity&.settings&.dig("quotas", "daily_ai_tokens_per_user") || @limits[:daily_ai_tokens_per_user]

    if user_daily > user_limit
      Rails.logger.warn "User #{user.id} exceeded daily token limit: #{user_daily}/#{user_limit}"
      notify_token_limit_exceeded(user, user_daily, user_limit)
    end

    # Check entity daily limit
    entity_daily = @token_tracker.get_entity_daily_total
    if entity_daily > @limits[:daily_ai_tokens]
      Rails.logger.warn "Entity #{@entity.id} exceeded daily token limit: #{entity_daily}/#{@limits[:daily_ai_tokens]}"
      notify_entity_token_limit_exceeded(entity_daily)
    end
  end

  def notify_token_limit_exceeded(user, usage, limit)
    ActiveSupport::Notifications.instrument("tokens.user_limit_exceeded", {
      user_id: user.id,
      entity_id: @entity.id,
      usage: usage,
      limit: limit
    })
  end

  def notify_entity_token_limit_exceeded(usage)
    ActiveSupport::Notifications.instrument("tokens.entity_limit_exceeded", {
      entity_id: @entity.id,
      usage: usage,
      limit: @limits[:daily_ai_tokens]
    })
  end

  def load_resource_limits
    # Load from entity settings, plan, or defaults
    base_limits = {
      # Concurrent operations
      concurrent_workflows: 3,
      concurrent_agents: 10,
      concurrent_api_calls: 20,

      # Daily limits
      daily_api_calls: 5000,
      daily_ai_tokens: 100_000,
      daily_ai_tokens_per_user: 10_000,
      daily_storage_mb: 1000,

      # Monthly limits
      monthly_ai_tokens: 3_000_000,
      monthly_ai_tokens_per_user: 300_000,

      # Rate limits (per minute)
      ai_calls_per_minute: 60,
      api_calls_per_minute: 100,
      tokens_per_minute: 10_000,

      # Resource limits
      memory_mb: 1024,
      cpu_threads: 4,

      # Cost limits
      daily_cost_usd: 10.0,
      monthly_cost_usd: 200.0
    }

    # Override with entity-specific limits
    if @entity.platform_tier == "premium"
      base_limits.merge(premium_limits)
    elsif @entity.platform_tier == "enterprise"
      base_limits.merge(enterprise_limits)
    else
      base_limits
    end
  end

  def premium_limits
    {
      concurrent_workflows: 10,
      concurrent_agents: 50,
      daily_api_calls: 50_000,
      daily_ai_tokens: 1_000_000,
      daily_ai_tokens_per_user: 100_000,
      monthly_ai_tokens: 30_000_000,
      monthly_ai_tokens_per_user: 3_000_000,
      tokens_per_minute: 50_000,
      memory_mb: 4096,
      cpu_threads: 8,
      daily_cost_usd: 50.0,
      monthly_cost_usd: 1000.0
    }
  end

  def enterprise_limits
    {
      concurrent_workflows: 100,
      concurrent_agents: 500,
      daily_api_calls: 500_000,
      daily_ai_tokens: 10_000_000,
      daily_ai_tokens_per_user: 1_000_000,
      monthly_ai_tokens: 300_000_000,
      monthly_ai_tokens_per_user: 30_000_000,
      tokens_per_minute: 500_000,
      memory_mb: 16384,
      cpu_threads: 32,
      daily_cost_usd: 500.0,
      monthly_cost_usd: 10_000.0
    }
  end

  def can_allocate?(requirements)
    requirements.each do |resource, amount|
      next unless @limits[resource]

      current = @usage[resource].value
      if current + amount > @limits[resource]
        Rails.logger.warn "Resource limit exceeded for #{resource}: #{current + amount} > #{@limits[resource]}"
        return false
      end
    end

    # Check cost limits
    if requirements[:estimated_cost]
      daily_cost = @cost_tracker.daily_total + requirements[:estimated_cost]
      if daily_cost > @limits[:daily_cost_usd]
        Rails.logger.warn "Daily cost limit would be exceeded: $#{daily_cost}"
        return false
      end
    end

    true
  end

  def allocate_resources(requirements)
    requirements.each do |resource, amount|
      next if resource == :estimated_cost
      @usage[resource].increment(amount)
    end
  end

  def deallocate_resources(requirements)
    requirements.each do |resource, amount|
      next if resource == :estimated_cost
      @usage[resource].decrement(amount)
    end
  end

  def calculate_cost(resource_type, amount)
    case resource_type
    when :ai_tokens
      amount * 0.00002 # $0.02 per 1K tokens
    when :api_calls
      amount * 0.0001 # $0.10 per 1K calls
    when :storage_mb
      amount * 0.0001 # $0.10 per GB per month
    else
      0
    end
  end

  def estimate_ai_cost(model, tokens)
    # Bedrock pricing (approximate)
    pricing = {
      "claude-3-opus" => { input: 0.015, output: 0.075 }, # per 1K tokens
      "claude-3-sonnet" => { input: 0.003, output: 0.015 },
      "claude-haiku-4-5" => { input: 0.001, output: 0.005 },
      "claude-3-haiku" => { input: 0.0025, output: 0.0125 },
      "gpt-4-turbo" => { input: 0.01, output: 0.03 },
      "gpt-3.5-turbo" => { input: 0.0005, output: 0.0015 }
    }

    model_pricing = pricing[model] || pricing["claude-haiku-4-5"]

    input_cost = (tokens[:input] || 0) / 1000.0 * model_pricing[:input]
    output_cost = (tokens[:output] || 0) / 1000.0 * model_pricing[:output]

    input_cost + output_cost
  end

  def estimate_api_cost(service)
    # Approximate costs for external services
    costs = {
      stripe: 0.001,
      mailgun: 0.0001,
      twilio: 0.0075,
      openai_embeddings: 0.0001,
      pinecone: 0.00001
    }

    costs[service] || 0.0001
  end

  def estimate_storage_cost(size_mb)
    # S3 storage cost
    size_gb = size_mb / 1024.0
    size_gb * 0.023 / 30 # Monthly cost divided by days
  end

  def breakdown_costs(operations)
    breakdown = Hash.new(0)

    operations.each do |op|
      if op[:type] == :ai_call
        breakdown[:ai_calls] += estimate_ai_cost(op[:model], op[:tokens])
      elsif op[:type] == :api_call
        breakdown[:api_calls] += estimate_api_cost(op[:service])
      elsif op[:type] == :storage
        breakdown[:storage] += estimate_storage_cost(op[:size_mb])
      end
    end

    breakdown
  end

  def rate_limits
    {
      ai_calls: @limits[:ai_calls_per_minute],
      api_calls: @limits[:api_calls_per_minute],
      tool_executions: 100,
      workflow_starts: 10
    }
  end

  def record_usage_metrics(resource_type, amount, duration)
    # Record to time-series database or metrics service
    Rails.logger.info "Resource usage: #{resource_type} - amount: #{amount}, duration: #{duration}s"

    # Store in Redis for analytics
    key = "resource_usage:#{@entity.id}:#{Date.current}"
    field = "#{resource_type}:#{Time.current.hour}"

    ($redis || Redis.new).hincrby(key, field, amount)
    ($redis || Redis.new).expire(key, 7.days)

    # Emit metrics event
    ActiveSupport::Notifications.instrument("resource.usage", {
      entity_id: @entity.id,
      resource_type: resource_type,
      amount: amount,
      duration: duration
    })
  end

  def calculate_usage_percentage(resource, current_value)
    limit = @limits[resource]
    return 0 unless limit && limit > 0

    (current_value.to_f / limit * 100).round(2)
  end

  def start_monitoring
    Thread.new do
      loop do
        begin
          # Clean up expired reservations
          cleanup_expired_reservations

          # Check for limit breaches
          check_limit_breaches

          # Update metrics
          update_usage_metrics

          sleep 60 # Check every minute
        rescue => e
          Rails.logger.error "ResourceManager monitoring error: #{e.message}"
        end
      end
    end
  end

  def cleanup_expired_reservations
    expired = []

    @lock.with_write_lock do
      @reservations.each do |id, reservation|
        if reservation[:expires_at] < Time.current
          expired << id
        end
      end

      expired.each do |id|
        reservation = @reservations.delete(id)
        deallocate_resources(reservation[:requirements])

        Rails.logger.warn "Cleaned up expired reservation: #{id}"
      end
    end
  end

  def check_limit_breaches
    @usage.each do |resource, atomic_value|
      current = atomic_value.value
      limit = @limits[resource]

      next unless limit

      percentage = calculate_usage_percentage(resource, current)

      if percentage >= 90
        notify_limit_warning(resource, percentage)
      elsif percentage >= 100
        notify_limit_breach(resource, current, limit)
      end
    end
  end

  def notify_limit_warning(resource, percentage)
    ActiveSupport::Notifications.instrument("resource.limit_warning", {
      entity_id: @entity.id,
      resource: resource,
      usage_percentage: percentage
    })
  end

  def notify_limit_breach(resource, current, limit)
    ActiveSupport::Notifications.instrument("resource.limit_breach", {
      entity_id: @entity.id,
      resource: resource,
      current: current,
      limit: limit
    })

    # Could also trigger alerts, emails, etc.
  end

  def update_usage_metrics
    metrics = usage_stats

    # Store snapshot
    key = "resource_metrics:#{@entity.id}:#{Time.current.to_i}"
    ($redis || Redis.new).setex(key, 1.hour, metrics.to_json)

    # Only broadcast if there's actual usage (avoid flooding logs in development)
    has_usage = metrics.any? { |_, data| data[:current] > 0 }
    return unless has_usage || Rails.env.production?

    # Update dashboard
    ActionCable.server.broadcast(
      "resource_usage_#{@entity.id}",
      {
        type: "usage_update",
        metrics: metrics,
        cost: @cost_tracker.current_totals
      }
    )
  end
end

# Cost tracking component
class CostTracker
  def initialize(entity)
    @entity = entity
    @costs = Concurrent::Hash.new { |h, k| h[k] = Concurrent::AtomicReference.new(0.0) }
  end

  def record_cost(category, amount, user: nil)
    @costs[category].update { |current| current + amount }
    @costs[:total].update { |current| current + amount }

    # Store in database for billing
    store_cost_record(category, amount, user: user)
  end

  def daily_total
    key = "daily_cost:#{@entity.id}:#{Date.current}"
    ($redis || Redis.new).get(key).to_f
  end

  def monthly_total
    key = "monthly_cost:#{@entity.id}:#{Date.current.strftime('%Y-%m')}"
    ($redis || Redis.new).get(key).to_f
  end

  def current_totals
    totals = {}
    @costs.each do |category, atomic_ref|
      totals[category] = atomic_ref.value
    end
    totals
  end

  private

  def store_cost_record(category, amount, user: nil)
    # Update daily total
    daily_key = "daily_cost:#{@entity.id}:#{Date.current}"
    ($redis || Redis.new).incrbyfloat(daily_key, amount)
    ($redis || Redis.new).expire(daily_key, 2.days)

    # Update monthly total
    monthly_key = "monthly_cost:#{@entity.id}:#{Date.current.strftime('%Y-%m')}"
    ($redis || Redis.new).incrbyfloat(monthly_key, amount)
    ($redis || Redis.new).expire(monthly_key, 35.days)

    # Update user-specific costs if user provided
    if user
      user_daily_key = "daily_cost:user:#{user.id}:#{Date.current}"
      ($redis || Redis.new).incrbyfloat(user_daily_key, amount)
      ($redis || Redis.new).expire(user_daily_key, 2.days)

      user_monthly_key = "monthly_cost:user:#{user.id}:#{Date.current.strftime('%Y-%m')}"
      ($redis || Redis.new).incrbyfloat(user_monthly_key, amount)
      ($redis || Redis.new).expire(user_monthly_key, 35.days)
    end

    # Store detailed record for billing
    ($redis || Redis.new).zadd(
      "cost_records:#{@entity.id}",
      Time.current.to_f,
      {
        category: category,
        amount: amount,
        user_id: user&.id,
        timestamp: Time.current.iso8601
      }.to_json
    )
  end
end

# Token tracking component
class TokenTracker
  def initialize(entity)
    @entity = entity
    @redis = ($redis || Redis.new)
  end

  def track_user_tokens(user, model, tokens, context = {})
    timestamp = Time.current.to_i
    input_tokens = tokens[:input] || 0
    output_tokens = tokens[:output] || 0
    total_tokens = input_tokens + output_tokens

    # Store detailed record
    record = {
      user_id: user.id,
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens,
      context: context,
      timestamp: Time.current.iso8601
    }

    # Store in time-series
    @redis.zadd(
      "tokens:user:#{user.id}:#{Date.current}",
      timestamp,
      record.to_json
    )
    @redis.expire("tokens:user:#{user.id}:#{Date.current}", 7.days)

    # Update counters
    update_user_counters(user, model, input_tokens, output_tokens)

    # Track by workflow/session if provided
    if context[:task_session_id]
      track_session_tokens(context[:task_session_id], model, tokens)
    end
  end

  def track_entity_tokens(model, tokens, context = {})
    timestamp = Time.current.to_i
    input_tokens = tokens[:input] || 0
    output_tokens = tokens[:output] || 0
    total_tokens = input_tokens + output_tokens

    # Store entity-level record
    record = {
      entity_id: @entity.id,
      model: model,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      total_tokens: total_tokens,
      context: context,
      timestamp: Time.current.iso8601
    }

    @redis.zadd(
      "tokens:entity:#{@entity.id}:#{Date.current}",
      timestamp,
      record.to_json
    )
    @redis.expire("tokens:entity:#{@entity.id}:#{Date.current}", 30.days)

    # Update entity counters
    update_entity_counters(model, input_tokens, output_tokens)
  end

  def track_session_tokens(session_id, model, tokens)
    key = "tokens:session:#{session_id}"

    @redis.hincrby(key, "#{model}:input", tokens[:input] || 0)
    @redis.hincrby(key, "#{model}:output", tokens[:output] || 0)
    @redis.hincrby(key, "total", (tokens[:input] || 0) + (tokens[:output] || 0))
    @redis.expire(key, 24.hours)
  end

  def get_user_stats(user, time_range = 24.hours)
    end_time = Time.current
    start_time = end_time - time_range

    # Get all records in time range
    records = get_user_records(user, start_time, end_time)

    # Calculate stats
    stats = calculate_stats(records)
    stats[:user_id] = user.id
    stats[:time_range] = { start: start_time, end: end_time }

    # Add current day/month totals
    stats[:daily_total] = get_user_daily_total(user)
    stats[:monthly_total] = get_user_monthly_total(user)

    stats
  end

  def get_entity_stats(time_range = 24.hours)
    end_time = Time.current
    start_time = end_time - time_range

    # Get all records in time range
    records = get_entity_records(start_time, end_time)

    # Calculate stats
    stats = calculate_stats(records)
    stats[:entity_id] = @entity.id
    stats[:time_range] = { start: start_time, end: end_time }

    # Add current day/month totals
    stats[:daily_total] = get_entity_daily_total
    stats[:monthly_total] = get_entity_monthly_total

    stats
  end

  def get_breakdown(user: nil, group_by: :model, time_range: 24.hours)
    end_time = Time.current
    start_time = end_time - time_range

    # Get records
    records = if user
      get_user_records(user, start_time, end_time)
    else
      get_entity_records(start_time, end_time)
    end

    # Group and aggregate
    breakdown = {}

    records.each do |record|
      data = JSON.parse(record, symbolize_names: true)
      key = case group_by
      when :model then data[:model]
      when :hour then Time.parse(data[:timestamp]).strftime("%Y-%m-%d %H:00")
      when :day then Time.parse(data[:timestamp]).strftime("%Y-%m-%d")
      when :user then data[:user_id]
      else data[:model]
      end

      breakdown[key] ||= { input: 0, output: 0, total: 0, count: 0 }
      breakdown[key][:input] += data[:input_tokens]
      breakdown[key][:output] += data[:output_tokens]
      breakdown[key][:total] += data[:total_tokens]
      breakdown[key][:count] += 1
    end

    # Sort by total tokens
    breakdown.sort_by { |_, v| -v[:total] }.to_h
  end

  def get_user_daily_total(user)
    key = "tokens:daily:user:#{user.id}:#{Date.current}"
    @redis.get(key).to_i
  end

  def get_user_monthly_total(user)
    key = "tokens:monthly:user:#{user.id}:#{Date.current.strftime('%Y-%m')}"
    @redis.get(key).to_i
  end

  def get_entity_daily_total
    key = "tokens:daily:entity:#{@entity.id}:#{Date.current}"
    @redis.get(key).to_i
  end

  def get_entity_monthly_total
    key = "tokens:monthly:entity:#{@entity.id}:#{Date.current.strftime('%Y-%m')}"
    @redis.get(key).to_i
  end

  private

  def update_user_counters(user, model, input_tokens, output_tokens)
    total = input_tokens + output_tokens

    # Daily counters
    daily_key = "tokens:daily:user:#{user.id}:#{Date.current}"
    @redis.incrby(daily_key, total)
    @redis.expire(daily_key, 2.days)

    # Monthly counters
    monthly_key = "tokens:monthly:user:#{user.id}:#{Date.current.strftime('%Y-%m')}"
    @redis.incrby(monthly_key, total)
    @redis.expire(monthly_key, 35.days)

    # Model-specific counters
    model_key = "tokens:model:user:#{user.id}:#{model}:#{Date.current}"
    @redis.hincrby(model_key, "input", input_tokens)
    @redis.hincrby(model_key, "output", output_tokens)
    @redis.expire(model_key, 7.days)
  end

  def update_entity_counters(model, input_tokens, output_tokens)
    total = input_tokens + output_tokens

    # Daily counters
    daily_key = "tokens:daily:entity:#{@entity.id}:#{Date.current}"
    @redis.incrby(daily_key, total)
    @redis.expire(daily_key, 2.days)

    # Monthly counters
    monthly_key = "tokens:monthly:entity:#{@entity.id}:#{Date.current.strftime('%Y-%m')}"
    @redis.incrby(monthly_key, total)
    @redis.expire(monthly_key, 35.days)

    # Model-specific counters
    model_key = "tokens:model:entity:#{@entity.id}:#{model}:#{Date.current}"
    @redis.hincrby(model_key, "input", input_tokens)
    @redis.hincrby(model_key, "output", output_tokens)
    @redis.expire(model_key, 30.days)
  end

  def get_user_records(user, start_time, end_time)
    keys = []
    current_date = start_time.to_date

    while current_date <= end_time.to_date
      keys << "tokens:user:#{user.id}:#{current_date}"
      current_date += 1.day
    end

    records = []
    keys.each do |key|
      records.concat(
        @redis.zrangebyscore(key, start_time.to_i, end_time.to_i)
      )
    end

    records
  end

  def get_entity_records(start_time, end_time)
    keys = []
    current_date = start_time.to_date

    while current_date <= end_time.to_date
      keys << "tokens:entity:#{@entity.id}:#{current_date}"
      current_date += 1.day
    end

    records = []
    keys.each do |key|
      records.concat(
        @redis.zrangebyscore(key, start_time.to_i, end_time.to_i)
      )
    end

    records
  end

  def calculate_stats(records)
    return empty_stats if records.empty?

    total_input = 0
    total_output = 0
    total_tokens = 0
    model_usage = Hash.new(0)

    records.each do |record|
      data = JSON.parse(record, symbolize_names: true)
      total_input += data[:input_tokens]
      total_output += data[:output_tokens]
      total_tokens += data[:total_tokens]
      model_usage[data[:model]] += data[:total_tokens]
    end

    {
      total_tokens: total_tokens,
      input_tokens: total_input,
      output_tokens: total_output,
      request_count: records.size,
      average_tokens_per_request: (total_tokens.to_f / records.size).round,
      model_usage: model_usage,
      input_output_ratio: total_input > 0 ? (total_output.to_f / total_input).round(2) : 0
    }
  end

  def empty_stats
    {
      total_tokens: 0,
      input_tokens: 0,
      output_tokens: 0,
      request_count: 0,
      average_tokens_per_request: 0,
      model_usage: {},
      input_output_ratio: 0
    }
  end
end
