# UpdateEmbeddingsJob
#
# Background job to update vector embeddings for agents, tools, and integrations.
# This ensures all records have up-to-date embeddings for RAG-based discovery.
#
# Usage:
#   UpdateEmbeddingsJob.perform_later(model: "all")
#   UpdateEmbeddingsJob.perform_later(model: "AgentPlugin")
#   UpdateEmbeddingsJob.perform_later(model: "ToolDefinition")
#   UpdateEmbeddingsJob.perform_later(model: "Integration")
#   UpdateEmbeddingsJob.perform_later(model: "IntegrationOperation")
#
class UpdateEmbeddingsJob < ApplicationJob
  queue_as :low

  # Rate limit to avoid overwhelming the embedding service
  BATCH_SIZE = 50
  DELAY_BETWEEN_BATCHES = 1.second

  def perform(model: "all", force: false)
    Rails.logger.info "🔄 Starting embedding update job for: #{model}"

    models_to_update = case model.to_s.downcase
    when "all"
      %w[AgentPlugin ToolDefinition Integration IntegrationOperation]
    when "agentplugin", "agent_plugin", "agents"
      %w[AgentPlugin]
    when "tooldefinition", "tool_definition", "tools"
      %w[ToolDefinition]
    when "integration", "integrations"
      %w[Integration]
    when "integrationoperation", "integration_operation", "operations"
      %w[IntegrationOperation]
    else
      [model.to_s]
    end

    stats = { updated: 0, skipped: 0, failed: 0 }

    models_to_update.each do |model_name|
      model_stats = update_model_embeddings(model_name, force: force)
      stats[:updated] += model_stats[:updated]
      stats[:skipped] += model_stats[:skipped]
      stats[:failed] += model_stats[:failed]
    end

    Rails.logger.info "✅ Embedding update complete: #{stats}"
    stats
  end

  private

  def update_model_embeddings(model_name, force: false)
    stats = { updated: 0, skipped: 0, failed: 0 }

    begin
      model_class = model_name.constantize
    rescue NameError => e
      Rails.logger.error "Unknown model: #{model_name}"
      return stats
    end

    # Check if model has embedding column
    unless model_class.column_names.include?("embedding")
      Rails.logger.warn "Model #{model_name} does not have embedding column"
      return stats
    end

    # Get records that need embedding updates
    scope = if force
      model_class.all
    else
      model_class.where(embedding: nil)
    end

    total = scope.count
    Rails.logger.info "📊 Processing #{total} #{model_name} records..."

    scope.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      batch.each do |record|
        begin
          if record.respond_to?(:update_embedding)
            record.update_embedding
            stats[:updated] += 1
          else
            # Generate embedding manually if no update_embedding method
            embedding_text = build_embedding_text(record, model_name)
            vector = AiAgents::VectorStore.instance.generate_embedding(embedding_text)
            
            if vector
              record.update_column(:embedding, vector)
              stats[:updated] += 1
            else
              stats[:skipped] += 1
            end
          end
        rescue => e
          Rails.logger.error "Failed to update embedding for #{model_name}##{record.id}: #{e.message}"
          stats[:failed] += 1
        end
      end

      # Rate limiting between batches
      sleep(DELAY_BETWEEN_BATCHES)
    end

    Rails.logger.info "📊 #{model_name}: #{stats[:updated]} updated, #{stats[:skipped]} skipped, #{stats[:failed]} failed"
    stats
  end

  def build_embedding_text(record, model_name)
    case model_name
    when "AgentPlugin"
      <<~TEXT
        Agent: #{record.name}
        Role: #{record.role}
        Description: #{record.description}
        Capabilities: #{record.agent_capabilities.map(&:capability_name).join(', ')}
      TEXT
    when "ToolDefinition"
      <<~TEXT
        Tool: #{record.name}
        Description: #{record.description}
        Type: #{record.execution_type}
        Parameters: #{record.parameters.to_json}
      TEXT
    when "Integration"
      <<~TEXT
        Integration: #{record.name}
        Category: #{record.category}
        Description: #{record.description}
        Base URL: #{record.api_base_url}
      TEXT
    when "IntegrationOperation"
      <<~TEXT
        Operation: #{record.name}
        Integration: #{record.integration&.name}
        Method: #{record.http_method}
        Path: #{record.path_template}
        Description: #{record.description}
      TEXT
    else
      record.try(:description) || record.try(:name) || record.to_s
    end
  end
end

