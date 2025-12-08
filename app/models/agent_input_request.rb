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
  # NOTE: broadcast_question_added removed - AskUserTool handles the broadcast
  # after the work item is created (so it can include work_item_id)
  after_update :broadcast_question_update, if: :saved_change_to_status?

  # Class methods for queue management
  def self.pending_count_for_session(session_id)
    for_session(session_id).active.count
  end

  def self.next_question_for_session(session_id)
    for_session(session_id).active.by_priority.first
  end

  def answer!(content, attachment: nil)
    # Store attachment info in context_data if provided
    updated_context = self.context_data || {}
    if attachment.present?
      updated_context['attachment'] = attachment
    end

    update!(
      response_content: content,
      status: 'answered',
      responded_at: Time.current,
      context_data: updated_context
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

  def mark_work_items_handled
    return unless status == 'answered' || status == 'cancelled' || status == 'skipped'
    
    # Find work items that reference this input request
    work_items = AgentWorkItem.where(
      "asset_data->>'input_request_id' = ?", id.to_s
    ).or(
      AgentWorkItem.where(agent_plugin_execution: agent_plugin_execution)
                   .where(work_type: 'action_required')
                   .where(requires_action: true)
    )
    
    work_items.find_each do |work_item|
      # Build update attributes based on status
      agent_name = display_agent_name
      
      update_attrs = {
        requires_action: false,
        read: true,
        asset_data: work_item.asset_data.merge(
          'answered_at' => Time.current.iso8601,
          'response' => response_content&.truncate(500),
          'previous_title' => work_item.title
        )
      }
      
      # Update title and priority to show in-progress state
      if status == 'answered'
        update_attrs[:title] = "#{agent_name} processing your response..."
        update_attrs[:priority] = 'normal'  # Lower priority since it's being handled
        update_attrs[:summary] = "Your response is being processed. Results coming soon."
      elsif status == 'skipped'
        update_attrs[:title] = "#{agent_name} - question skipped"
        update_attrs[:priority] = 'low'
        update_attrs[:summary] = "This question was skipped."
      end
      
      work_item.update!(update_attrs)
      Rails.logger.info "📬 Marked work item #{work_item.id} as handled (input request #{id} #{status})"
      
      # Broadcast work inbox update so UI refreshes
      if session_id.present?
        ScoutChannel.broadcast_to(session_id, {
          type: 'work_inbox_update',
          action: 'item_updated',
          work_item_id: work_item.id,
          new_title: update_attrs[:title],
          new_status: status
        })
      end
    end
  end
end

