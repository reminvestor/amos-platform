# frozen_string_literal: true

# Central service for managing AMOS Work Token operations
# Handles usage tracking, billing, and token management
class WorkTokenService
  attr_reader :user, :entity, :billing_account

  def initialize(user:, entity: nil)
    @user = user
    @entity = entity
    @billing_account = UserBillingAccount.for_user(user)
    @config = BillingConfiguration.current
  end

  # Track AI token usage
  def track_ai_usage(input_tokens:, output_tokens:, model:, source: nil, metadata: {})
    work_tokens = @config.calculate_ai_work_tokens(
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      model: model
    )
    
    return { success: true, tokens_charged: 0 } if work_tokens.zero?
    
    # Calculate raw cost for tracking (uses actual model pricing)
    raw_cost_cents = @config.calculate_ai_raw_cost_cents(
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      model: model
    )
    uplifted_cost_cents = (raw_cost_cents * (1 + @config.uplift_percentage / 100.0)).round
    
    debit_tokens(
      amount: work_tokens,
      category: 'ai_tokens',
      description: "AI usage: #{model} (#{input_tokens + output_tokens} tokens)",
      source: source,
      raw_cost_cents: raw_cost_cents,
      uplifted_cost_cents: uplifted_cost_cents,
      breakdown: { model => work_tokens },
      metadata: metadata.merge(
        model: model,
        input_tokens: input_tokens,
        output_tokens: output_tokens
      )
    )
  end

  # Track email sending
  def track_email_usage(email_count:, source: nil, metadata: {})
    work_tokens = @config.calculate_email_work_tokens(email_count: email_count)
    
    return { success: true, tokens_charged: 0 } if work_tokens.zero?
    
    # SES pricing: ~$0.10 per 1000 emails
    raw_cost_cents = (email_count * 0.01).round # $0.0001 per email = 0.01 cents
    uplifted_cost_cents = (raw_cost_cents * (1 + @config.uplift_percentage / 100.0)).round
    
    debit_tokens(
      amount: work_tokens,
      category: 'email',
      description: "Email sending: #{email_count} email(s)",
      source: source,
      raw_cost_cents: raw_cost_cents,
      uplifted_cost_cents: uplifted_cost_cents,
      metadata: metadata.merge(email_count: email_count)
    )
  end

  # Track storage usage
  def track_storage_usage(megabytes:, source: nil, metadata: {})
    work_tokens = @config.calculate_storage_work_tokens(megabytes: megabytes)
    
    return { success: true, tokens_charged: 0 } if work_tokens.zero?
    
    # S3 pricing: ~$0.023 per GB/month = $0.000023 per MB/month
    raw_cost_cents = (megabytes * 0.0023).round
    uplifted_cost_cents = (raw_cost_cents * (1 + @config.uplift_percentage / 100.0)).round
    
    debit_tokens(
      amount: work_tokens,
      category: 'storage',
      description: "Storage: #{megabytes.round(2)} MB",
      source: source,
      raw_cost_cents: raw_cost_cents,
      uplifted_cost_cents: uplifted_cost_cents,
      metadata: metadata.merge(megabytes: megabytes)
    )
  end

  # Track API call usage
  def track_api_usage(call_count:, source: nil, metadata: {})
    work_tokens = @config.calculate_api_work_tokens(call_count: call_count)
    
    return { success: true, tokens_charged: 0 } if work_tokens.zero?
    
    debit_tokens(
      amount: work_tokens,
      category: 'api_call',
      description: "API calls: #{call_count}",
      source: source,
      raw_cost_cents: 0, # API calls have minimal direct cost
      uplifted_cost_cents: 0,
      metadata: metadata.merge(call_count: call_count)
    )
  end

  # Track other AWS compute usage (Lambda, Textract, Rekognition, Comprehend, etc.)
  # service_type examples: 'lambda', 'textract', 'rekognition', 'comprehend', 'transcribe', 'polly'
  # cost_cents is the raw AWS cost in cents
  def track_other_compute(cost_cents:, service_type:, description: nil, source: nil, metadata: {})
    cost_usd = cost_cents / 100.0
    work_tokens = @config.calculate_other_compute_work_tokens(cost_usd: cost_usd)
    
    return { success: true, tokens_charged: 0 } if work_tokens.zero?
    
    uplifted_cost_cents = (cost_cents * (1 + @config.uplift_percentage / 100.0)).round
    desc = description || "#{service_type.titleize} compute"
    
    debit_tokens(
      amount: work_tokens,
      category: 'other_compute',
      description: desc,
      source: source,
      raw_cost_cents: cost_cents,
      uplifted_cost_cents: uplifted_cost_cents,
      breakdown: { service_type => work_tokens },
      metadata: metadata.merge(
        service_type: service_type,
        raw_cost_cents: cost_cents
      )
    )
  end

  # Convenience methods for specific AWS services
  def track_lambda_usage(invocations:, duration_ms:, memory_mb:, source: nil, metadata: {})
    # Lambda pricing: $0.0000166667 per GB-second
    gb_seconds = (duration_ms / 1000.0) * (memory_mb / 1024.0) * invocations
    cost_cents = (gb_seconds * 0.00166667).round(4) # Convert to cents
    
    track_other_compute(
      cost_cents: [cost_cents, 0.01].max, # Minimum 0.01 cents
      service_type: 'lambda',
      description: "Lambda: #{invocations} invocation(s), #{duration_ms}ms",
      source: source,
      metadata: metadata.merge(invocations: invocations, duration_ms: duration_ms, memory_mb: memory_mb)
    )
  end

  def track_textract_usage(pages:, feature_type: 'detect_text', source: nil, metadata: {})
    # Textract pricing varies by feature
    cost_per_page = case feature_type
    when 'detect_text' then 0.15        # $0.0015 per page = 0.15 cents
    when 'analyze_document' then 0.50   # $0.005 per page
    when 'analyze_expense' then 1.00    # $0.01 per page
    when 'analyze_id' then 1.50         # $0.015 per page
    else 0.15
    end
    
    cost_cents = (pages * cost_per_page).round(2)
    
    track_other_compute(
      cost_cents: cost_cents,
      service_type: 'textract',
      description: "Textract #{feature_type}: #{pages} page(s)",
      source: source,
      metadata: metadata.merge(pages: pages, feature_type: feature_type)
    )
  end

  def track_rekognition_usage(images:, feature_type: 'detect_labels', source: nil, metadata: {})
    # Rekognition pricing varies by feature
    cost_per_image = case feature_type
    when 'detect_labels', 'detect_faces' then 0.10  # $0.001 per image
    when 'detect_text' then 0.10
    when 'recognize_celebrities' then 0.10
    when 'detect_moderation_labels' then 0.10
    when 'face_compare' then 0.10
    else 0.10
    end
    
    cost_cents = (images * cost_per_image).round(2)
    
    track_other_compute(
      cost_cents: cost_cents,
      service_type: 'rekognition',
      description: "Rekognition #{feature_type}: #{images} image(s)",
      source: source,
      metadata: metadata.merge(images: images, feature_type: feature_type)
    )
  end

  def track_transcribe_usage(seconds:, source: nil, metadata: {})
    # Transcribe pricing: $0.024 per minute = $0.0004 per second = 0.04 cents/sec
    cost_cents = (seconds * 0.04).round(2)
    
    track_other_compute(
      cost_cents: cost_cents,
      service_type: 'transcribe',
      description: "Transcribe: #{(seconds / 60.0).round(1)} minute(s)",
      source: source,
      metadata: metadata.merge(seconds: seconds)
    )
  end

  def track_polly_usage(characters:, voice_type: 'standard', source: nil, metadata: {})
    # Polly pricing per million characters
    cost_per_million = case voice_type
    when 'standard' then 400   # $4 per million = 400 cents
    when 'neural' then 1600    # $16 per million
    when 'long_form' then 1000 # $10 per million
    else 400
    end
    
    cost_cents = (characters.to_f / 1_000_000 * cost_per_million).round(2)
    
    track_other_compute(
      cost_cents: [cost_cents, 0.01].max,
      service_type: 'polly',
      description: "Polly #{voice_type}: #{characters} characters",
      source: source,
      metadata: metadata.merge(characters: characters, voice_type: voice_type)
    )
  end

  def track_comprehend_usage(units:, feature_type: 'detect_sentiment', source: nil, metadata: {})
    # Comprehend pricing per unit (100 characters)
    cost_per_unit = case feature_type
    when 'detect_sentiment', 'detect_entities', 'detect_key_phrases' then 0.01 # $0.0001 per unit
    when 'detect_syntax' then 0.005
    when 'detect_pii' then 0.01
    else 0.01
    end
    
    cost_cents = (units * cost_per_unit).round(2)
    
    track_other_compute(
      cost_cents: [cost_cents, 0.01].max,
      service_type: 'comprehend',
      description: "Comprehend #{feature_type}: #{units} units",
      source: source,
      metadata: metadata.merge(units: units, feature_type: feature_type)
    )
  end

  # Check if user has sufficient balance
  def has_balance?(tokens_needed = 1000)
    @billing_account.has_sufficient_balance?(tokens_needed)
  end

  # Get current balance
  def balance
    @billing_account.work_token_balance
  end

  # Purchase tokens
  def purchase_tokens(amount_usd:, trigger: 'manual')
    @billing_account.purchase_tokens!(
      amount_usd: amount_usd,
      trigger: trigger
    )
  end

  # Get usage summary
  def usage_summary(days: 30)
    summaries = WorkTokenUsageSummary
      .where(user_billing_account: @billing_account)
      .for_date_range(days.days.ago.to_date, Date.current)
    
    {
      total_tokens_used: summaries.total_tokens,
      total_cost_usd: summaries.total_cost_usd,
      by_category: summaries.by_category,
      daily_totals: summaries.daily_totals,
      period_days: days
    }
  end

  # Get recent transactions
  def recent_transactions(limit: 50)
    @billing_account.work_token_transactions.recent.limit(limit)
  end

  private

  def debit_tokens(amount:, category:, description:, source: nil, raw_cost_cents: 0, uplifted_cost_cents: 0, breakdown: {}, metadata: {})
    unless @billing_account.has_sufficient_balance?(amount)
      # Try auto-replenishment first
      if @billing_account.can_auto_replenish?
        begin
          @billing_account.purchase_tokens!(
            amount_usd: @billing_account.auto_replenish_amount_usd,
            trigger: 'auto_replenish'
          )
        rescue UserBillingAccount::PaymentFailedError => e
          return {
            success: false,
            error: 'insufficient_balance',
            message: "Insufficient balance and auto-replenishment failed: #{e.message}",
            tokens_needed: amount,
            balance: @billing_account.work_token_balance
          }
        end
      else
        return {
          success: false,
          error: 'insufficient_balance',
          message: 'Insufficient work token balance',
          tokens_needed: amount,
          balance: @billing_account.work_token_balance
        }
      end
    end
    
    # Debit the tokens
    @billing_account.debit_tokens!(
      amount: amount,
      category: category,
      description: description,
      source: source,
      metadata: metadata.merge(
        raw_cost_cents: raw_cost_cents,
        uplifted_cost_cents: uplifted_cost_cents,
        uplift_percentage: @config.uplift_percentage
      )
    )
    
    # Record in usage summary
    WorkTokenUsageSummary.record_usage!(
      billing_account: @billing_account,
      user: @user,
      entity: @entity,
      category: category,
      tokens: amount,
      raw_cost_cents: raw_cost_cents,
      uplifted_cost_cents: uplifted_cost_cents,
      breakdown: breakdown
    )
    
    {
      success: true,
      tokens_charged: amount,
      balance_remaining: @billing_account.work_token_balance,
      category: category
    }
  rescue UserBillingAccount::InsufficientBalanceError => e
    {
      success: false,
      error: 'insufficient_balance',
      message: e.message,
      tokens_needed: amount,
      balance: @billing_account.work_token_balance
    }
  end

  # Raw AI cost calculation is now in BillingConfiguration.calculate_ai_raw_cost_cents
end

