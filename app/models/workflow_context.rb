class WorkflowContext < ApplicationRecord
  belongs_to :workflow_execution
  belongs_to :task_session
  
  # Store different types of context data
  enum data_type: {
    user_input: 'user_input',
    file_reference: 'file_reference',
    extracted_data: 'extracted_data',
    ai_decision: 'ai_decision',
    step_output: 'step_output'
  }
  
  # Validations
  validates :key, presence: true
  validates :data_type, presence: true
  
  # Scopes for easy querying
  scope :files, -> { where(data_type: 'file_reference') }
  scope :user_inputs, -> { where(data_type: 'user_input') }
  scope :by_key, ->(key) { where(key: key) }
  
  # Helper methods
  def file?
    data_type == 'file_reference'
  end
  
  def as_file_info
    return nil unless file?
    {
      url: value['url'],
      filename: value['filename'],
      content_type: value['content_type'],
      size: value['size'],
      asset_id: value['asset_id']
    }
  end
  
  # Class methods for easy context management
  class << self
    def store_file(workflow_execution, key, file_info)
      create!(
        workflow_execution: workflow_execution,
        task_session: workflow_execution.task_session,
        key: key,
        value: file_info,
        data_type: 'file_reference',
        metadata: { 
          stored_at: Time.current,
          original_filename: file_info['filename'] 
        }
      )
    end
    
    def store_user_input(workflow_execution, key, input_data)
      create!(
        workflow_execution: workflow_execution,
        task_session: workflow_execution.task_session,
        key: key,
        value: input_data,
        data_type: 'user_input',
        metadata: { stored_at: Time.current }
      )
    end
    
    def get_context_for_workflow(workflow_execution)
      where(workflow_execution: workflow_execution)
        .order(created_at: :desc)
        .group_by(&:key)
        .transform_values(&:first)
    end
  end
end




