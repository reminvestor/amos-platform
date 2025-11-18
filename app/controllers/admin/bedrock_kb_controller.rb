# Admin controller for managing AWS Bedrock Knowledge Bases
class Admin::BedrockKbController < Admin::BaseController
  before_action :set_entity, only: [:show, :create_kb, :enable, :disable, :sync]

  def index
    @entities = Entity.all.order(:name)
    @statistics = RagModeSelector.mode_statistics
  end

  def show
    @selector = RagModeSelector.new(@entity)
    @kb_service = Aws::BedrockKnowledgeBaseService.instance

    # Get KB status if exists
    if @entity.bedrock_knowledge_base_id.present?
      begin
        @kb_details = @kb_service.send(:describe_knowledge_base, @entity.bedrock_knowledge_base_id)
        @ingestion_status = @kb_service.check_ingestion_status(@entity) if @entity.bedrock_last_ingestion_job_id.present?
      rescue => e
        @kb_error = e.message
      end
    end
  end

  def create_kb
    kb_service = Aws::BedrockKnowledgeBaseService.instance

    begin
      kb = kb_service.create_knowledge_base(@entity)

      flash[:success] = "Successfully created Bedrock Knowledge Base: #{kb.knowledge_base_id}"
      redirect_to admin_bedrock_kb_path(@entity)
    rescue => e
      flash[:error] = "Failed to create Knowledge Base: #{e.message}"
      redirect_to admin_bedrock_kb_index_path
    end
  end

  def enable
    selector = RagModeSelector.new(@entity)

    begin
      selector.switch_mode!(:bedrock_kb)
      flash[:success] = "Enabled Bedrock KB for #{@entity.name}"
    rescue => e
      flash[:error] = "Failed to enable Bedrock KB: #{e.message}"
    end

    redirect_to admin_bedrock_kb_path(@entity)
  end

  def disable
    @entity.update!(use_bedrock_kb: false)
    flash[:success] = "Disabled Bedrock KB for #{@entity.name}"
    redirect_to admin_bedrock_kb_path(@entity)
  end

  def sync
    kb_service = Aws::BedrockKnowledgeBaseService.instance

    begin
      job = kb_service.start_ingestion_job(@entity.bedrock_knowledge_base_id, @entity)
      flash[:success] = "Started ingestion job: #{job.ingestion_job_id}"
    rescue => e
      flash[:error] = "Failed to start sync: #{e.message}"
    end

    redirect_to admin_bedrock_kb_path(@entity)
  end

  private

  def set_entity
    @entity = Entity.find(params[:id] || params[:entity_id])
  end
end
