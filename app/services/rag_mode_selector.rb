# RAG Mode Selector Service
#
# Intelligently selects the best RAG backend based on:
# - Entity configuration (use_bedrock_kb flag)
# - Bedrock KB availability (knowledge_base_id present)
# - Fallback to pgvector + Pinecone
#
# Usage:
#   selector = RagModeSelector.new(entity)
#   mode = selector.select_mode
#   service = selector.get_service
#
class RagModeSelector
  attr_reader :entity, :mode

  # Available RAG modes
  MODES = {
    bedrock_kb: {
      name: 'AWS Bedrock Knowledge Base',
      description: 'Fully managed RAG with OpenSearch Serverless',
      requirements: [:bedrock_enabled, :knowledge_base_exists]
    },
    hybrid: {
      name: 'Hybrid (pgvector + Pinecone)',
      description: 'Local pgvector + optional Pinecone cloud storage',
      requirements: []
    },
    pgvector_only: {
      name: 'PostgreSQL pgvector',
      description: 'Local vector search only',
      requirements: []
    }
  }.freeze

  def initialize(entity)
    @entity = entity
    @mode = select_mode
  end

  # Select the best RAG mode based on entity configuration
  def select_mode
    # Priority 1: Bedrock KB if explicitly enabled and available
    if bedrock_kb_available?
      Rails.logger.info "🎯 RAG Mode: Bedrock KB (Knowledge Base: #{@entity.bedrock_knowledge_base_id})"
      return :bedrock_kb
    end

    # Priority 2: Hybrid mode (pgvector + Pinecone) if Pinecone configured
    if pinecone_available?
      Rails.logger.info "🎯 RAG Mode: Hybrid (pgvector + Pinecone)"
      return :hybrid
    end

    # Priority 3: pgvector only (default fallback)
    Rails.logger.info "🎯 RAG Mode: pgvector only"
    :pgvector_only
  end

  # Get the appropriate RAG service instance
  def get_service
    case @mode
    when :bedrock_kb
      # Use HybridRagQueryService with Bedrock KB enabled
      # It will automatically use Bedrock KB if use_bedrock_kb is true
      HybridRagQueryService.new(@entity)
    when :hybrid, :pgvector_only
      # Use HybridRagQueryService (handles both cases)
      HybridRagQueryService.new(@entity)
    else
      raise "Unknown RAG mode: #{@mode}"
    end
  end

  # Check if Bedrock KB is available for this entity
  def bedrock_kb_available?
    @entity.use_bedrock_kb &&
      @entity.bedrock_knowledge_base_id.present? &&
      ENV['AWS_BEDROCK_KB_ENABLED'] != 'false'
  end

  # Check if Pinecone is configured
  def pinecone_available?
    ENV['PINECONE_API_KEY'].present? &&
      ENV['PINECONE_ENVIRONMENT'].present?
  end

  # Get mode information
  def mode_info
    MODES[@mode] || { name: 'Unknown', description: 'Unknown mode' }
  end

  # Check if current mode meets requirements
  def mode_valid?
    info = mode_info
    requirements = info[:requirements] || []

    requirements.all? do |req|
      case req
      when :bedrock_enabled
        @entity.use_bedrock_kb
      when :knowledge_base_exists
        @entity.bedrock_knowledge_base_id.present?
      when :pinecone_configured
        pinecone_available?
      else
        true
      end
    end
  end

  # Get all available modes for this entity
  def available_modes
    modes = []

    modes << :bedrock_kb if bedrock_kb_available?
    modes << :hybrid if pinecone_available?
    modes << :pgvector_only # Always available

    modes
  end

  # Switch RAG mode (updates entity configuration)
  def switch_mode!(new_mode)
    raise ArgumentError, "Invalid mode: #{new_mode}" unless MODES.key?(new_mode)

    case new_mode
    when :bedrock_kb
      unless @entity.bedrock_knowledge_base_id.present?
        raise "Cannot enable Bedrock KB: No knowledge base configured for entity #{@entity.id}"
      end
      @entity.update!(use_bedrock_kb: true)
      Rails.logger.info "✅ Switched entity #{@entity.id} to Bedrock KB mode"

    when :hybrid, :pgvector_only
      @entity.update!(use_bedrock_kb: false)
      Rails.logger.info "✅ Switched entity #{@entity.id} to #{new_mode} mode"
    end

    @mode = select_mode
  end

  # Class method for quick mode selection
  def self.for_entity(entity)
    new(entity)
  end

  # Get mode statistics for admin dashboard
  def self.mode_statistics
    {
      total_entities: Entity.count,
      bedrock_kb_enabled: Entity.where(use_bedrock_kb: true).count,
      bedrock_kb_configured: Entity.where.not(bedrock_knowledge_base_id: nil).count,
      hybrid_mode: Entity.where(use_bedrock_kb: false).count,
      modes: MODES
    }
  end
end
