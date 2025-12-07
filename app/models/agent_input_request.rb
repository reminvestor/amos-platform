class AgentInputRequest < ApplicationRecord
  belongs_to :agent_plugin_execution

  validates :question, presence: true
  validates :status, inclusion: { in: %w[pending answered cancelled skipped] }

  scope :pending, -> { where(status: 'pending') }
  scope :answered, -> { where(status: 'answered') }
  scope :active, -> { pending.where(skipped: false).where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }
  scope :for_session, ->(session_id) { where(session_id: session_id) }
  scope :expired, -> { where('expires_at < ?', Time.current) }

  # After answering, mark any associated work items as handled
  after_update :mark_work_items_handled, if: :saved_change_to_status?
  after_create :broadcast_question_added
  after_update :broadcast_question_update, if: :saved_change_to_status?

  # Class methods for queue management
  def self.pending_count_for_session(session_id)
    for_session(session_id).active.count
  end

  def self.next_question_for_session(session_id)
    for_session(session_id).active.by_priority.first
  end

  def answer!(content)
    update!(
      response_content: content,
      status: 'answered',
      responded_at: Time.current
    )
    resume_agent_execution!
  end

  def skip!(reason: nil)
    update!(
      status: 'skipped',
      skipped: true,
      skipped_reason: reason
    )
    resume_agent_execution!(skipped: true)
  end

  def cancel!
    update!(status: 'cancelled')
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # For display in the overlay
  def display_agent_name
    agent_name.presence || agent_plugin_execution&.agent_plugin&.name || 'Agent'
  end

  def display_agent_icon
    agent_icon.presence || agent_plugin_execution&.agent_plugin&.try(:icon) || '🤖'
  end

  def as_queue_json
    {
      id: id,
      question: question,
      agent_name: display_agent_name,
      agent_icon: display_agent_icon,
      priority: priority,
      created_at: created_at.iso8601,
      expires_at: expires_at&.iso8601,
      context: context_data,
      execution_id: agent_plugin_execution_id
    }
  end

  private

  def broadcast_question_added
    Rails.logger.info "🔔 AgentInputRequest#broadcast_question_added called for ID #{id}"
    Rails.logger.info "   session_id: #{session_id.inspect}"
    Rails.logger.info "   agent_name: #{agent_name.inspect}"
    
    if session_id.blank?
      Rails.logger.warn "⚠️ AgentInputRequest#broadcast_question_added - session_id is blank, skipping broadcast"
      return
    end
    
    broadcast_data = {
      type: 'question_queue_update',
      action: 'added',
      question: as_queue_json,
      pending_count: self.class.pending_count_for_session(session_id)
    }
    
    Rails.logger.info "📡 Broadcasting question_queue_update to session #{session_id}: #{broadcast_data.inspect}"
    
    ScoutChannel.broadcast_to(session_id, broadcast_data)
    
    Rails.logger.info "✅ Broadcast sent for question_queue_update"
  rescue => e
    Rails.logger.error "❌ AgentInputRequest#broadcast_question_added failed: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end

  def broadcast_question_update
    return unless session_id.present?
    
    ScoutChannel.broadcast_to(session_id, {
      type: 'question_queue_update',
      action: status, # answered, skipped, cancelled
      question_id: id,
      pending_count: self.class.pending_count_for_session(session_id)
    })
  end

  def resume_agent_execution!(**options)
    execution = agent_plugin_execution
    return unless execution&.status == 'waiting_for_input'

    # Queue the job to resume the agent with the response
    ResumeAgentExecutionJob.perform_later(
      execution.id,
      response_content,
      options.merge(
        variable_name: variable_name,
        skipped: options[:skipped] || false
      )
    )
  end

  private

  def mark_work_items_handled
    return unless status == 'answered' || status == 'cancelled'
    
    # Find work items that reference this input request
    work_items = AgentWorkItem.where(
      "asset_data->>'input_request_id' = ?", id.to_s
    ).or(
      AgentWorkItem.where(agent_plugin_execution: agent_plugin_execution)
                   .where(work_type: 'action_required')
                   .where(requires_action: true)
    )
    
    work_items.find_each do |work_item|
      work_item.update!(
        requires_action: false,
        read: true,
        asset_data: work_item.asset_data.merge(
          'answered_at' => Time.current.iso8601,
          'response' => response_content&.truncate(500)
        )
      )
      Rails.logger.info "📬 Marked work item #{work_item.id} as handled (input request #{id} #{status})"
    end
  end
end

