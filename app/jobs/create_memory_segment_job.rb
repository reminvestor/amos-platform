# CreateMemorySegmentJob
#
# Creates memory segments (L3 summaries) from conversation history.
# Called automatically when message thresholds are reached.
#
class CreateMemorySegmentJob < ApplicationJob
  queue_as :low_priority

  def perform(user_id, entity_id, segment_type = 'daily', options = {})
    @user = User.find_by(id: user_id)
    @entity = Entity.find_by(id: entity_id)
    @segment_type = segment_type
    @options = options.with_indifferent_access

    return unless @user && @entity

    Rails.logger.info "🧠 CreateMemorySegmentJob: Creating #{segment_type} segment"

    case segment_type
    when 'daily'
      create_daily_segment
    when 'weekly'
      create_weekly_segment
    when 'topic'
      create_topic_segment(@options[:topic])
    end

  rescue => e
    Rails.logger.error "CreateMemorySegmentJob error: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  private

  def create_daily_segment
    # Get today's unsummarized messages
    messages = ScoutMessage.where(user_id: @user.id, entity_id: @entity.id)
                          .where("created_at > ?", 24.hours.ago)
                          .where(summarized: false)
                          .order(created_at: :asc)

    return if messages.count < 10

    # Get time range
    period_start = messages.first.created_at
    period_end = messages.last.created_at

    # Format for AI
    conversation_text = messages.map do |m|
      role = m.role == 'user' ? 'User' : 'Scout'
      "#{role}: #{m.content}"
    end.join("\n\n")

    # Generate summary with AI
    summary_data = generate_summary(conversation_text, 'daily')
    return unless summary_data

    # Create segment
    segment = MemorySegment.create!(
      user: @user,
      entity: @entity,
      segment_type: 'daily',
      period_start: period_start,
      period_end: period_end,
      message_count: messages.count,
      summary: summary_data['summary'],
      key_topics: summary_data['topics'].to_json,
      key_decisions: summary_data['decisions'].to_json,
      action_items: summary_data['action_items'].to_json,
      context_snapshot: summary_data['context_for_future']
    )

    # Mark messages as summarized
    messages.update_all(summarized: true, summary_id: segment.id, memory_layer: 'l3')

    Rails.logger.info "🧠 Created daily segment: #{segment.summary.truncate(100)}"

    # Check if we need weekly rollup
    check_weekly_rollup_needed
  end

  def create_weekly_segment
    # Get this week's daily segments
    daily_segments = MemorySegment.where(user: @user, entity: @entity)
                                  .where(segment_type: 'daily')
                                  .where("period_start > ?", 7.days.ago)
                                  .where(active: true)
                                  .order(period_start: :asc)

    return if daily_segments.count < 3

    # Combine daily summaries
    combined_text = daily_segments.map do |seg|
      "#{seg.period_label}:\n#{seg.summary}\nTopics: #{seg.topics_array.join(', ')}"
    end.join("\n\n---\n\n")

    # Generate weekly summary
    summary_data = generate_summary(combined_text, 'weekly')
    return unless summary_data

    # Create weekly segment
    segment = MemorySegment.create!(
      user: @user,
      entity: @entity,
      segment_type: 'weekly',
      period_start: daily_segments.first.period_start,
      period_end: daily_segments.last.period_end,
      message_count: daily_segments.sum(:message_count),
      summary: summary_data['summary'],
      key_topics: summary_data['topics'].to_json,
      key_decisions: summary_data['decisions'].to_json,
      action_items: summary_data['action_items'].to_json,
      context_snapshot: summary_data['context_for_future']
    )

    # Deactivate the daily segments (weekly replaces them)
    daily_segments.update_all(active: false)

    Rails.logger.info "🧠 Created weekly segment: #{segment.summary.truncate(100)}"
  end

  def create_topic_segment(topic)
    return unless topic.present?

    # Find messages related to this topic
    messages = ScoutMessage.where(user_id: @user.id, entity_id: @entity.id)
                          .where("topics ILIKE ?", "%#{topic}%")
                          .where(summarized: false)
                          .order(created_at: :asc)
                          .limit(50)

    return if messages.count < 5

    conversation_text = messages.map do |m|
      role = m.role == 'user' ? 'User' : 'Scout'
      "#{role}: #{m.content}"
    end.join("\n\n")

    summary_data = generate_summary(conversation_text, 'topic', topic: topic)
    return unless summary_data

    MemorySegment.create!(
      user: @user,
      entity: @entity,
      segment_type: 'topic',
      period_start: messages.first.created_at,
      period_end: messages.last.created_at,
      message_count: messages.count,
      summary: summary_data['summary'],
      key_topics: [topic].to_json,
      key_decisions: summary_data['decisions'].to_json,
      action_items: summary_data['action_items'].to_json,
      context_snapshot: summary_data['context_for_future']
    )

    Rails.logger.info "🧠 Created topic segment for '#{topic}'"
  end

  def generate_summary(text, type, topic: nil)
    ai_service = BedrockService.new(user: @user, entity: @entity)

    prompt = case type
    when 'daily'
      daily_summary_prompt(text)
    when 'weekly'
      weekly_summary_prompt(text)
    when 'topic'
      topic_summary_prompt(text, topic)
    end

    response = ai_service.send_message(
      "You are a conversation analyst. Return only valid JSON.",
      [{ role: "user", content: prompt }],
      model: "claude-haiku-4-5-20251001",
      max_tokens: 800
    )

    # Parse response
    json_match = response.match(/\{[\s\S]*\}/m)
    return nil unless json_match

    JSON.parse(json_match[0])
  rescue JSON::ParserError => e
    Rails.logger.warn "Summary JSON parse failed: #{e.message}"
    nil
  rescue => e
    Rails.logger.error "Summary generation failed: #{e.message}"
    nil
  end

  def daily_summary_prompt(text)
    <<~PROMPT
      Summarize this day's conversation for an AI assistant's memory.

      CONVERSATION:
      #{text.truncate(8000)}

      Return JSON:
      {
        "summary": "2-3 sentence summary of what was discussed and accomplished today",
        "topics": ["topic1", "topic2"],
        "decisions": ["any decisions made"],
        "action_items": ["pending tasks or follow-ups"],
        "context_for_future": "Key context to remember for tomorrow"
      }

      Focus on what the user wanted and what was done. Be concise.
    PROMPT
  end

  def weekly_summary_prompt(text)
    <<~PROMPT
      Create a weekly summary from these daily summaries.

      DAILY SUMMARIES:
      #{text.truncate(6000)}

      Return JSON:
      {
        "summary": "3-4 sentence summary of the week's activities and progress",
        "topics": ["main themes this week"],
        "decisions": ["key decisions made"],
        "action_items": ["ongoing or pending items"],
        "context_for_future": "Important context for next week"
      }

      Focus on patterns, progress, and important ongoing work.
    PROMPT
  end

  def topic_summary_prompt(text, topic)
    <<~PROMPT
      Summarize all conversations about "#{topic}".

      CONVERSATION EXCERPTS:
      #{text.truncate(6000)}

      Return JSON:
      {
        "summary": "Summary of all #{topic} discussions",
        "topics": ["#{topic}"],
        "decisions": ["decisions made about #{topic}"],
        "action_items": ["pending #{topic} tasks"],
        "context_for_future": "Current status of #{topic}"
      }
    PROMPT
  end

  def check_weekly_rollup_needed
    # Count daily segments from this week
    daily_count = MemorySegment.where(user: @user, entity: @entity)
                               .where(segment_type: 'daily')
                               .where("period_start > ?", 7.days.ago)
                               .where(active: true)
                               .count

    if daily_count >= 5
      # Queue weekly rollup
      self.class.perform_later(@user.id, @entity.id, 'weekly')
    end
  end
end
