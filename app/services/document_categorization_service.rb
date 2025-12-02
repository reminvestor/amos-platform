class DocumentCategorizationService
  def initialize(entity)
    @entity = entity
    @ai_client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  end
  
  def categorize(document)
    Rails.logger.info "🤖 Auto-categorizing document: #{document.display_title}"
    
    # Get document content preview
    content = get_content_preview(document)
    
    # Get existing subjects and tags
    existing_subjects = @entity.document_subjects.pluck(:name, :description)
    existing_tags = @entity.document_tags.pluck(:name).uniq
    
    # Use AI to suggest categories
    suggestions = ai_suggest_categories(content, existing_subjects, existing_tags)
    
    # Apply suggestions
    apply_suggestions(document, suggestions)
    
    Rails.logger.info "✅ Document categorized with #{suggestions[:tags].count} tags and #{suggestions[:subjects].count} subjects"
    
    suggestions
  rescue => e
    Rails.logger.error "❌ Document categorization failed: #{e.message}"
    { subjects: [], tags: [], summary: nil }
  end
  
  private
  
  def get_content_preview(document)
    # Build content preview from document metadata and chunks
    preview = []
    
    # Add basic metadata
    preview << "Title: #{document.display_title}"
    preview << "Filename: #{document.original_filename}"
    preview << "Type: #{document.content_type}"
    preview << "Author: #{document.author}" if document.author.present?
    preview << "Date: #{document.document_date || document.created_at}"
    
    # Add summary if available
    preview << "\nSummary: #{document.summary}" if document.summary.present?
    
    # Add content from first few chunks
    if document.rag_chunks.any?
      preview << "\nContent Preview:"
      document.rag_chunks.limit(5).each do |chunk|
        preview << chunk.content.truncate(500)
      end
    end
    
    # Add any extracted metadata
    if document.docling_metadata.present?
      preview << "\nExtracted Metadata:"
      preview << document.docling_metadata.to_json
    end
    
    preview.join("\n")
  end
  
  def ai_suggest_categories(content, existing_subjects, existing_tags)
    prompt = build_categorization_prompt(content, existing_subjects, existing_tags)
    
    response = @ai_client.chat(
      parameters: {
        model: "gpt-4",
        messages: [
          {
            role: "system",
            content: "You are a document categorization assistant. Analyze documents and suggest appropriate categories, tags, and summaries. Always respond with valid JSON."
          },
          {
            role: "user",
            content: prompt
          }
        ],
        temperature: 0.3,
        max_tokens: 1000
      }
    )
    
    parse_ai_response(response)
  end
  
  def build_categorization_prompt(content, existing_subjects, existing_tags)
    <<~PROMPT
      Analyze the following document and suggest categories:

      DOCUMENT CONTENT:
      #{content.truncate(3000)}

      EXISTING COLLECTIONS/SUBJECTS:
      #{existing_subjects.map { |name, desc| "- #{name}: #{desc}" }.join("\n")}

      EXISTING TAGS:
      #{existing_tags.join(', ')}

      Please provide categorization suggestions in the following JSON format:
      {
        "subjects": ["Subject Name 1", "Subject Name 2"],
        "new_subjects": [
          {"name": "New Subject", "description": "Brief description"}
        ],
        "tags": ["tag1", "tag2", "tag3"],
        "new_tags": ["newtag1", "newtag2"],
        "summary": "A brief 1-2 sentence summary of the document",
        "entities": {
          "people": ["Person Name"],
          "organizations": ["Company Name"],
          "locations": ["City, State"]
        },
        "document_type": "contract|report|presentation|email|memo|other",
        "confidence": 0.95
      }

      Guidelines:
      - Prefer existing subjects/tags when appropriate
      - Suggest new ones only when necessary
      - Keep tags lowercase, single words or short phrases
      - Provide 3-7 relevant tags
      - Assign to 1-3 most relevant subjects
      - Extract key entities if present
      - Assess your confidence level (0-1)
    PROMPT
  end
  
  def parse_ai_response(response)
    content = response.dig("choices", 0, "message", "content")
    
    # Extract JSON from the response
    json_match = content.match(/\{.*\}/m)
    return default_suggestions unless json_match
    
    suggestions = JSON.parse(json_match[0])
    
    {
      subjects: suggestions["subjects"] || [],
      new_subjects: suggestions["new_subjects"] || [],
      tags: suggestions["tags"] || [],
      new_tags: suggestions["new_tags"] || [],
      summary: suggestions["summary"],
      entities: suggestions["entities"] || {},
      document_type: suggestions["document_type"],
      confidence: suggestions["confidence"] || 0.5
    }
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse AI response: #{e.message}"
    default_suggestions
  end
  
  def default_suggestions
    {
      subjects: [],
      new_subjects: [],
      tags: [],
      new_tags: [],
      summary: nil,
      entities: {},
      document_type: 'other',
      confidence: 0
    }
  end
  
  def apply_suggestions(document, suggestions)
    # Apply high-confidence suggestions automatically
    if suggestions[:confidence] > 0.7
      # Update summary if provided
      if suggestions[:summary].present? && document.summary.blank?
        document.update(summary: suggestions[:summary])
      end
      
      # Create new subjects if needed
      suggestions[:new_subjects].each do |subject_data|
        @entity.document_subjects.find_or_create_by(
          name: subject_data["name"]
        ) do |s|
          s.description = subject_data["description"]
        end
      end
      
      # Assign to subjects
      subject_names = suggestions[:subjects]
      if subject_names.any?
        subjects = @entity.document_subjects.where(name: subject_names)
        document.assign_to_subjects(subjects.pluck(:id))
      end
      
      # Add tags
      all_tags = suggestions[:tags] + suggestions[:new_tags]
      if all_tags.any?
        document.add_tags(all_tags, suggestions[:document_type] || 'custom')
      end
      
      # Store entities in metadata
      if suggestions[:entities].any?
        document.update(
          keywords: (document.keywords || []) + suggestions[:entities].values.flatten.uniq
        )
      end
    end
    
    # Always return suggestions for review
    suggestions
  end
end
