class EmbeddingService
  MODEL = 'text-embedding-ada-002' # OpenAI's embedding model
  BEDROCK_MODEL = 'amazon.titan-embed-text-v1' # AWS Bedrock embedding model
  
  def initialize
    @provider = ENV.fetch('EMBEDDING_PROVIDER', 'bedrock').downcase
  end
  
  # Generate embedding for text
  def generate(text)
    return nil if text.blank?
    
    case @provider
    when 'openai'
      generate_openai_embedding(text)
    when 'bedrock'
      generate_bedrock_embedding(text)
    else
      raise "Unknown embedding provider: #{@provider}"
    end
  end
  
  # Generate embeddings for multiple texts (batch)
  def generate_batch(texts)
    texts.map { |text| generate(text) }
  end
  
  # Calculate cosine similarity between two embeddings
  def similarity(embedding1, embedding2)
    return 0.0 if embedding1.nil? || embedding2.nil?
    
    # Cosine similarity calculation
    dot_product = embedding1.zip(embedding2).sum { |a, b| a * b }
    magnitude1 = Math.sqrt(embedding1.sum { |a| a**2 })
    magnitude2 = Math.sqrt(embedding2.sum { |a| a**2 })
    
    return 0.0 if magnitude1 == 0 || magnitude2 == 0
    
    dot_product / (magnitude1 * magnitude2)
  end
  
  private
  
  def generate_openai_embedding(text)
    # Would integrate with OpenAI API
    # For now, return nil as placeholder
    Rails.logger.info "Would generate OpenAI embedding for text: #{text.truncate(100)}"
    nil
  end
  
  def generate_bedrock_embedding(text)
    begin
      bedrock = Aws::BedrockRuntime::Client.new(
        region: ENV.fetch('AWS_REGION', 'us-east-1')
      )
      
      request_body = {
        inputText: text.truncate(8000) # Titan has 8K token limit
      }
      
      response = bedrock.invoke_model(
        model_id: BEDROCK_MODEL,
        content_type: 'application/json',
        accept: 'application/json',
        body: request_body.to_json
      )
      
      result = JSON.parse(response.body.read)
      embedding = result['embedding']
      
      Rails.logger.info "Generated Bedrock embedding, dimension: #{embedding&.length}"
      embedding
      
    rescue Aws::BedrockRuntime::Errors::ServiceError => e
      Rails.logger.error "Bedrock embedding error: #{e.message}"
      nil
    rescue => e
      Rails.logger.error "Embedding generation error: #{e.class}: #{e.message}"
      nil
    end
  end
end
