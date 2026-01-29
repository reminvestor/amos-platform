# frozen_string_literal: true

# HubMessage
#
# A message in the Collaborative Intelligence Hub.
# Can be sent by humans OR agents - they're equal participants.
#
class HubMessage < ApplicationRecord
  # Associations
  belongs_to :hub_thread, counter_cache: :message_count, touch: :last_activity_at
  belongs_to :sender, polymorphic: true  # User or AgentPlugin
  belongs_to :reply_to, class_name: 'HubMessage', optional: true
  belongs_to :agent_input_request, optional: true
  belongs_to :agent_plugin_execution, optional: true

  has_many :replies, class_name: 'HubMessage', foreign_key: :reply_to_id, dependent: :nullify

  # Message types
  TEXT = 'text'.freeze
  HANDOFF_REQUEST = 'handoff_request'.freeze
  HANDOFF_COMPLETE = 'handoff_complete'.freeze
  QUESTION = 'question'.freeze
  STATUS_UPDATE = 'status_update'.freeze
  AGENT_THINKING = 'agent_thinking'.freeze
  SYSTEM = 'system'.freeze
  FILE_SHARE = 'file_share'.freeze
  GIF = 'gif'.freeze  # NEW: Giphy GIF messages
  EMOJI = 'emoji'.freeze  # NEW: Large emoji-only messages

  TYPES = [TEXT, HANDOFF_REQUEST, HANDOFF_COMPLETE, QUESTION, 
           STATUS_UPDATE, AGENT_THINKING, SYSTEM, FILE_SHARE, GIF, EMOJI].freeze

  HANDOFF_STATUSES = %w[pending accepted completed cancelled].freeze

  # Validations
  validates :content, presence: true
  validates :message_type, presence: true, inclusion: { in: TYPES }
  validates :handoff_status, inclusion: { in: HANDOFF_STATUSES }, allow_nil: true
  validate :sender_is_participant

  # Scopes
  scope :not_deleted, -> { where(deleted: false) }
  scope :by_type, ->(type) { where(message_type: type) }
  scope :pending_responses, -> { where(needs_response: true) }
  scope :handoffs, -> { where(is_handoff: true) }
  scope :recent_first, -> { order(created_at: :desc) }
  scope :oldest_first, -> { order(created_at: :asc) }
  scope :from_agents, -> { where(sender_type: 'AgentPlugin') }
  scope :from_users, -> { where(sender_type: 'User') }

  # Callbacks
  after_create :notify_participants
  after_create :create_agent_input_request_if_needed
  after_create :parse_and_notify_mentions
  after_create :trigger_agent_response_if_dm

  # ============================================
  # SENDER HELPERS
  # ============================================

  def from_agent?
    sender_type == 'AgentPlugin'
  end

  def from_user?
    sender_type == 'User'
  end

  def sender_name
    return sender.name if sender.respond_to?(:name) && sender_type == 'AgentPlugin'
    return sender.full_name if sender.respond_to?(:full_name)
    return sender.email.split('@').first if sender.respond_to?(:email)
    sender.to_s
  end

  def sender_avatar
    if from_agent?
      sender.respond_to?(:icon) ? sender.icon : '🤖'
    else
      sender.respond_to?(:avatar_url) ? sender.avatar_url : nil
    end
  end

  # ============================================
  # REACTIONS
  # ============================================

  def add_reaction(user, emoji)
    current = reactions || {}
    current[emoji] ||= []
    current[emoji] << user.id unless current[emoji].include?(user.id)
    update!(reactions: current)
    broadcast_reaction_update
  end

  def remove_reaction(user, emoji)
    current = reactions || {}
    return unless current[emoji]
    
    current[emoji].delete(user.id)
    current.delete(emoji) if current[emoji].empty?
    update!(reactions: current)
    broadcast_reaction_update
  end

  def reaction_summary
    (reactions || {}).map do |emoji, user_ids|
      { emoji: emoji, count: user_ids.size, user_ids: user_ids }
    end
  end

  # ============================================
  # HANDOFF ACTIONS
  # ============================================

  def accept_handoff!(by_user)
    return unless is_handoff && handoff_status == 'pending'

    update!(
      handoff_status: 'accepted',
      needs_response: false,
      metadata: metadata.merge(
        accepted_by: by_user.id,
        accepted_at: Time.current.iso8601
      )
    )

    # Create follow-up message
    hub_thread.add_message(
      sender: by_user,
      content: "#{by_user.name} accepted the handoff",
      message_type: SYSTEM
    )
  end

  def complete_handoff!(by_user, feedback: nil)
    return unless is_handoff && handoff_status == 'accepted'

    update!(
      handoff_status: 'completed',
      metadata: metadata.merge(
        completed_by: by_user.id,
        completed_at: Time.current.iso8601,
        feedback: feedback
      )
    )
  end

  # ============================================
  # RESPONSE HANDLING
  # ============================================

  def respond!(response_content, by:)
    return unless needs_response

    # Create response message
    response = hub_thread.add_message(
      sender: by,
      content: response_content,
      message_type: TEXT,
      reply_to: self
    )

    # Clear the needs_response flag
    update!(needs_response: false)

    # If linked to AgentInputRequest, answer it
    if agent_input_request.present?
      agent_input_request.answer!(response_content)
    end

    response
  end

  # ============================================
  # EDIT & DELETE
  # ============================================

  def edit!(new_content, by:)
    return false unless sender == by
    return false if deleted?

    update!(
      content: new_content,
      edited: true,
      edited_at: Time.current
    )
  end

  def soft_delete!(by:)
    update!(
      deleted: true,
      deleted_at: Time.current,
      metadata: metadata.merge(deleted_by: by.id)
    )
  end

  # ============================================
  # SERIALIZATION
  # ============================================

  def as_broadcast_json
    {
      id: id,
      thread_id: hub_thread_id,
      sender: {
        id: sender_id,
        type: sender_type,
        name: sender_name,
        avatar: sender_avatar
      },
      content: content,
      message_type: message_type,
      needs_response: needs_response,
      is_handoff: is_handoff,
      handoff_status: handoff_status,
      attachments: attachments,
      actions: actions,
      reactions: reaction_summary,
      reply_to_id: reply_to_id,
      created_at: created_at.iso8601,
      edited: edited,
      edited_at: edited_at&.iso8601
    }
  end

  def as_context_json
    # Minimal version for agent context loading
    {
      id: id,
      sender_type: sender_type,
      sender_name: sender_name,
      content: content,
      message_type: message_type,
      created_at: created_at.iso8601
    }
  end

  private

  def sender_is_participant
    return if hub_thread.nil?
    
    unless hub_thread.participant?(sender)
      errors.add(:sender, 'must be a participant in the thread')
    end
  end

  def notify_participants
    # Handled by HubThread#add_message for unread counts
    # Push notifications are handled in background
    SendHubMessagePushNotificationsJob.perform_later(id)
  end

  def create_agent_input_request_if_needed
    # If this is an agent asking a question, create AgentInputRequest
    # This bridges to the existing system
    return unless from_agent? && needs_response && message_type == QUESTION
    return if agent_input_request.present?

    # Find an active execution for this agent
    execution = sender.agent_plugin_executions.running.last
    return unless execution

    request = AgentInputRequest.create!(
      agent_plugin_execution: execution,
      question: content,
      status: 'pending',
      session_id: hub_thread.metadata['session_id'],
      agent_name: sender.name,
      agent_icon: sender.respond_to?(:icon) ? sender.icon : '🤖'
    )

    update!(agent_input_request: request)
  end

  # Trigger agent to respond when user sends message in agent DM thread
  def trigger_agent_response_if_dm
    # Only trigger if:
    # 1. This is a user message (not from agent)
    # 2. This is a DM thread
    # 3. The other participant is an agent
    return unless from_user?
    return unless hub_thread.thread_type == HubThread::DM
    
    # Find the agent participant in this DM
    agent_participant = hub_thread.hub_participants.find { |p| p.participant_type == 'AgentPlugin' }
    return unless agent_participant
    
    agent = agent_participant.participant
    return unless agent&.status == 'active'
    
    Rails.logger.info "💬 [Hub] Triggering agent response from #{agent.name} in DM thread #{hub_thread_id}"
    
    # Build context for agent execution
    context_data = {
      session_id: hub_thread.metadata['session_id'] || SecureRandom.uuid,
      entity_id: hub_thread.entity_id,
      respond_in_hub: true,
      hub_thread_id: hub_thread_id,
      triggered_by: 'hub_dm'
    }
    
    # Include canvas context if provided (so agent knows what user is viewing)
    canvas_context = metadata&.dig('canvas_context')
    if canvas_context.present?
      context_data[:canvas_context] = canvas_context
      Rails.logger.info "🎨 [Hub] Including canvas context for agent: #{canvas_context}"
    end
    
    # Include attachment URLs if present
    if attachments.present?
      context_data[:attached_files] = attachments
    end
    
    # Include recent conversation context, respecting fresh start (context_access_from)
    # Use messages_for_participant to properly filter by context_access_from
    recent_messages = hub_thread.messages_for_participant(sender)
                                .where.not(id: id)
                                .order(created_at: :desc)
                                .limit(10)
                                .reverse
    
    conversation_context = recent_messages.map do |msg|
      {
        role: msg.from_agent? ? 'assistant' : 'user',
        content: msg.content
      }
    end
    context_data[:conversation_history] = conversation_context
    
    Rails.logger.info "💬 [Hub] Loaded #{conversation_context.length} messages for conversation context (respecting fresh start)"
    
    # Create execution record
    # Note: task_description is stored in input_context, not as a direct column
    # Valid statuses: running, completed, failed, waiting_for_input, cancelled
    execution = agent.agent_plugin_executions.create!(
      user: sender,
      input_context: context_data.merge(task: content),
      status: 'running'
    )
    
    # Queue the agent execution job
    AgentPluginExecutionJob.perform_later(
      execution.id,
      content,
      context_data.stringify_keys
    )
    
    Rails.logger.info "🚀 [Hub] Queued agent execution #{execution.id} for thread #{hub_thread_id}"
  rescue => e
    Rails.logger.error "❌ [Hub] Failed to trigger agent response: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def broadcast_reaction_update
    HubChannel.broadcast_to_thread(hub_thread_id, {
      type: 'reaction_update',
      message_id: id,
      reactions: reaction_summary
    })
  end

  # ============================================
  # MENTIONS (@tagging)
  # ============================================

  def parse_and_notify_mentions
    return unless content.present?
    return if sender_type == 'AgentPlugin' # Agents don't trigger mention notifications
    
    mentioned_user_ids = extract_mentions
    return if mentioned_user_ids.empty?
    
    # Store mentions in metadata
    update_column(:metadata, metadata.merge(mentioned_users: mentioned_user_ids))
    
    # Create notifications for mentioned users
    notify_mentioned_users(mentioned_user_ids)
  end

  def extract_mentions
    # Extract @username or @"First Last" patterns
    # Matches: @john, @john.doe, @"John Doe"
    mention_patterns = content.scan(/@"([^"]+)"|@([\w.]+)/).flatten.compact
    
    return [] if mention_patterns.empty?
    
    # Find users in this thread by name or email
    thread_users = hub_thread.user_participants
    
    mentioned_users = mention_patterns.map do |pattern|
      # Try to match by name parts or email
      thread_users.find do |user|
        name_match = user.full_name.downcase.include?(pattern.downcase) ||
                    user.first_name.downcase == pattern.downcase ||
                    user.last_name.downcase == pattern.downcase ||
                    user.email.split('@').first.downcase == pattern.downcase
        name_match
      end
    end.compact.uniq
    
    mentioned_users.map(&:id)
  end

  def mentioned_users
    user_ids = metadata&.dig('mentioned_users') || []
    return [] if user_ids.empty?
    
    User.where(id: user_ids)
  end

  def notify_mentioned_users(user_ids)
    users = User.where(id: user_ids)
    
    users.each do |user|
      # Create in-app notification
      create_mention_notification(user)
      
      # Could add email notification here if user preferences allow
    end
  end

  def create_mention_notification(user)
    # Using metadata to track mentions for now
    # Could create a separate Notification model later
    Rails.logger.info "📬 #{sender_name} mentioned #{user.full_name} in message #{id}"
    
    # Broadcast mention notification
    HubChannel.broadcast_to_user(user.id, {
      type: 'mention',
      message_id: id,
      thread_id: hub_thread_id,
      thread_name: hub_thread.display_name(for_participant: user),
      sender_name: sender_name,
      content_preview: content.truncate(100),
      created_at: created_at.iso8601
    })
  end

  # Replace @mentions with clickable links in HTML display
  def content_with_mentions_highlighted
    return content unless metadata&.dig('mentioned_users')&.any?
    
    highlighted = content.dup
    mentioned_users.each do |user|
      # Replace various mention formats with highlighted version
      patterns = [
        "@#{user.first_name}",
        "@#{user.last_name}",
        "@#{user.first_name}.#{user.last_name}",
        "@#{user.email.split('@').first}",
        "@\"#{user.full_name}\""
      ]
      
      patterns.each do |pattern|
        if highlighted.include?(pattern)
          highlighted.gsub!(pattern, "<span class='mention' data-user-id='#{user.id}'>#{pattern}</span>")
        end
      end
    end
    
    highlighted
  end

  def broadcast_reaction_update
    HubChannel.broadcast_to_thread(hub_thread_id, {
      type: 'reaction_update',
      message_id: id,
      reactions: reaction_summary
    })
  end
end
