class AgentInputRequest < ApplicationRecord
  belongs_to :agent_plugin_execution

  validates :question, presence: true
  validates :status, inclusion: { in: %w[pending answered cancelled] }

  scope :pending, -> { where(status: 'pending') }
  scope :answered, -> { where(status: 'answered') }

  # After answering, mark any associated work items as handled
  after_update :mark_work_items_handled, if: :saved_change_to_status?

  def answer!(content)
    update!(
      response_content: content,
      status: 'answered',
      responded_at: Time.current
    )
  end

  def cancel!
    update!(status: 'cancelled')
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

