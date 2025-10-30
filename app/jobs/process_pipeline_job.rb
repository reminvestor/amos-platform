class ProcessPipelineJob < ApplicationJob
  queue_as :pipeline

  def perform(pipeline_execution_id)
    pipeline_execution = PipelineExecution.find(pipeline_execution_id)

    Rails.logger.info "🔄 Processing pipeline #{pipeline_execution.id} in state: #{pipeline_execution.status}"

    orchestrator = Pipeline::Orchestrator.new(pipeline_execution)
    orchestrator.process!
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "Pipeline execution not found: #{e.message}"
  rescue => e
    Rails.logger.error "Pipeline processing failed: #{e.message}\n#{e.backtrace.first(10).join("\n")}"
    pipeline_execution&.fail!(e.message)
    raise
  end
end
