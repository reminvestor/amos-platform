# SummarizeConversationJob
#
# Automatically summarizes older conversation segments when chats get long.
# This enables Scout to maintain context over extended conversations without
# exceeding token limits.
#
# Strategy:
# - Threshold: 30 messages trigger first summarization
# - Summarize: Messages 1-20 (keeping last 10+ in active window)
# - Subsequent: Every 15-20 new messages, summarize the previous batch
# - Rolling: Keep last 2-3 summaries active for progressive context
#
class SummarizeConversationJob < ApplicationJob
  queue_as :low_priority

  # Configuration
  SUMMARIZATION_THRESHOLD = 30  # Total messages before first summary
  BATCH_SIZE = 20               # Messages to summarize at once
  WINDOW_SIZE = 15              # Messages to keep in active window
  MAX_ACTIVE_SUMMARIES = 3      # Rolling window of summaries to keep

  def perform(session_id, user_id, entity_id, options = {})
    @session_id = session_id
    @user = User.find_by(id: user_id)
    @entity = Entity.find_by(id: entity_id)
    @options = options.with_indifferent_access

    return unless @user && @entity

    Rails.logger.info "📚 SummarizeConversationJob: Starting for session #{session_id}"

    # Get all messages for this session
    all_messages = ScoutMessage.where(session_id: session_id)
                               .order(created_at: :asc)
                               .select(:id, :role, :content, :created_at)

    # Use .size instead of .count to avoid SQL error with select columns
    total_count = all_messages.size
    Rails.logger.info "📚 Total messages: #{total_count}"

    return if total_count < SUMMARIZATION_THRESHOLD

    # Determine what needs summarizing
    last_summary = ConversationSummary.active.for_session(session_id).by_recency.first
    last_summarized_index = last_summary&.message_end_index || 0

    # Calculate range to summarize
    # Leave WINDOW_SIZE messages unsummarized for the active context
    messages_to_keep = WINDOW_SIZE
    summarize_end_index = total_count - messages_to_keep
    summarize_start_index = last_summarized_index + 1

    # Need at least BATCH_SIZE/2 messages to make summarization worthwhile
    messages_to_summarize_count = summarize_end_index - summarize_start_index + 1
    if messages_to_summarize_count < (BATCH_SIZE / 2)
      Rails.logger.info "📚 Not enough messages to summarize (#{messages_to_summarize_count}), skipping"
      return
    end

    Rails.logger.info "📚 Summarizing messages #{summarize_start_index}-#{summarize_end_index}"

    # Get the actual messages to summarize
    messages_array = all_messages.to_a
    messages_to_summarize = messages_array[(summarize_start_index - 1)..(summarize_end_index - 1)]

    return if messages_to_summarize.blank?

    # Format for summarization
    formatted_messages = messages_to_summarize.map do |m|
      { role: m.role, content: m.content }
    end

    # Create the summary
    ai_service = BedrockService.new(user: @user, entity: @entity)
    summary = ConversationSummary.create_from_messages(
      user: @user,
      entity: @entity,
      session_id: session_id,
      messages: formatted_messages,
      start_index: summarize_start_index,
      ai_service: ai_service
    )

    if summary
      Rails.logger.info "📚 Created summary: #{summary.summary.truncate(100)}"
      Rails.logger.info "📚 Compression: #{summary.compression_ratio}% reduction"

      # Deactivate old summaries beyond our rolling window
      deactivate_old_summaries
    else
      Rails.logger.warn "📚 Failed to create summary"
    end

  rescue => e
    Rails.logger.error "SummarizeConversationJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  def deactivate_old_summaries
    # Keep only MAX_ACTIVE_SUMMARIES active
    summaries = ConversationSummary.active
                                   .for_session(@session_id)
                                   .by_recency
                                   .to_a

    if summaries.count > MAX_ACTIVE_SUMMARIES
      # Deactivate oldest ones
      summaries[MAX_ACTIVE_SUMMARIES..-1].each do |old_summary|
        old_summary.update!(active: false)
        Rails.logger.info "📚 Deactivated old summary covering messages #{old_summary.message_start_index}-#{old_summary.message_end_index}"
      end
    end
  end
end
