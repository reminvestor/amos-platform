class DocumentSearchService
  def initialize(entity)
    @entity = entity
  end
  
  def search(query:, filters: {})
    # Always use hybrid approach - try semantic first, fallback to keyword
    semantic_search(query, filters)
  end
  
  private
  
  def semantic_search(query, filters)
    # Use HybridRagQueryService for semantic search
    begin
      service = HybridRagQueryService.new(@entity)
      results = service.query(query, top_k: 10)
      
      # Extract unique document IDs from chunks
      document_ids = results[:chunks].map { |chunk| chunk[:document_id] || chunk[:rag_document_id] }.compact.uniq
      
      if document_ids.any?
        # Get the actual documents
        documents = RagDocument.joins(:rag_store)
                              .where(rag_stores: { entity_id: @entity.id })
                              .where(id: document_ids)
        
        # Apply additional filters
        documents = apply_filters(documents, filters)
        
        # Convert to array for consistent handling
        documents = documents.to_a if documents.respond_to?(:to_a)
        
        # Sort by relevance (document order in results)
        document_order = document_ids.each_with_index.to_h
        documents = documents.sort_by { |doc| document_order[doc.id] || 999 }
        
        {
          success: true,
          documents: documents,
          total_count: documents.count,
          search_type: 'semantic'
        }
      else
        # No semantic results, fallback to keyword
        keyword_search(query, filters)
      end
    rescue => e
      Rails.logger.error "Semantic search failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Fallback to keyword search
      keyword_search(query, filters)
    end
  end
  
  def keyword_search(query, filters)
    # Start with all entity documents
    documents = RagDocument.joins(:rag_store)
                          .where(rag_stores: { entity_id: @entity.id })
    
    # Full text search if query present
    if query.present?
      # Try PostgreSQL full text search first
      if documents.respond_to?(:search)
        documents = documents.search(query)
      else
        # Use PostgreSQL full-text search on chunks
        # Use plainto_tsquery for more forgiving search (handles hyphens, etc.)
        documents = documents.left_joins(:rag_chunks)
                            .where(
                              "to_tsvector('english', rag_documents.original_filename || ' ' || 
                                          COALESCE(rag_documents.title, '') || ' ' || 
                                          COALESCE(rag_documents.summary, '') || ' ' || 
                                          COALESCE(rag_documents.author, '')) @@ plainto_tsquery('english', :query) OR
                               to_tsvector('english', rag_chunks.content) @@ plainto_tsquery('english', :query)",
                              query: query
                            )
                            .distinct
      end
    end
    
    # Apply filters
    documents = apply_filters(documents, filters)
    
    # If no results with full-text search and we had a query, try ILIKE as fallback
    if query.present? && documents.count == 0
      search_term = "%#{query}%"
      documents = RagDocument.joins(:rag_store)
                            .where(rag_stores: { entity_id: @entity.id })
                            .left_joins(:rag_chunks)
                            .where(
                              "rag_documents.original_filename ILIKE :term OR 
                               rag_documents.title ILIKE :term OR 
                               rag_documents.summary ILIKE :term OR
                               rag_documents.author ILIKE :term OR
                               rag_chunks.content ILIKE :term",
                              term: search_term
                            )
                            .distinct
                            
      # Apply filters again
      documents = apply_filters(documents, filters)
    end
    
    # Convert to array if needed
    documents = documents.to_a if documents.respond_to?(:to_a)
    
    {
      success: true,
      documents: documents,
      total_count: documents.count,
      search_type: 'keyword'
    }
  end
  
  def apply_filters(documents, filters)
    # Convert to relation if array
    if documents.is_a?(Array)
      document_ids = documents.map(&:id)
      documents = RagDocument.where(id: document_ids)
    end
    
    # Subject filter
    if filters[:subject_id].present?
      documents = documents.joins(:document_subjects)
                          .where(document_subjects: { id: filters[:subject_id] })
    end
    
    # Tag filter
    if filters[:tags].present?
      tag_names = filters[:tags].split(',').map(&:strip)
      documents = documents.joins(:document_tags)
                          .where(document_tags: { name: tag_names })
                          .distinct
    end
    
    # Date range filter
    if filters[:date_range].present?
      date_range = parse_date_range(filters[:date_range])
      documents = documents.where(created_at: date_range)
    end
    
    # Content type filter
    if filters[:content_type].present?
      types = filters[:content_type].split(',')
      conditions = types.map { "content_type LIKE ?" }
      values = types.map { |t| "%#{t}%" }
      documents = documents.where(conditions.join(' OR '), *values)
    end
    
    # Author filter
    if filters[:author].present?
      documents = documents.where("author ILIKE ?", "%#{filters[:author]}%")
    end
    
    # Language filter
    if filters[:language].present?
      documents = documents.where(language: filters[:language])
    end
    
    documents
  end
  
  def build_pinecone_filters(filters)
    pinecone_filters = {}
    
    # Add filters that Pinecone might support
    if filters[:content_type].present?
      pinecone_filters[:content_type] = filters[:content_type].split(',')
    end
    
    if filters[:date_from].present? || filters[:date_to].present?
      # Convert dates to timestamps for Pinecone
      date_from = filters[:date_from] || 100.years.ago
      date_to = filters[:date_to] || Time.current
      pinecone_filters[:created_at] = {
        "$gte" => date_from.to_i,
        "$lte" => date_to.to_i
      }
    end
    
    pinecone_filters
  end
  
  def parse_date_range(range_string)
    case range_string
    when 'today'
      Date.current.beginning_of_day..Date.current.end_of_day
    when 'yesterday'
      1.day.ago.beginning_of_day..1.day.ago.end_of_day
    when 'last_7_days'
      7.days.ago.beginning_of_day..Time.current
    when 'last_30_days'
      30.days.ago.beginning_of_day..Time.current
    when 'last_90_days'
      90.days.ago.beginning_of_day..Time.current
    when 'this_month'
      Date.current.beginning_of_month..Date.current.end_of_month
    when 'last_month'
      1.month.ago.beginning_of_month..1.month.ago.end_of_month
    when 'this_year'
      Date.current.beginning_of_year..Date.current.end_of_year
    when 'all_time'
      100.years.ago..Time.current
    else
      # Try to parse custom range
      if range_string.include?('..')
        dates = range_string.split('..')
        Date.parse(dates[0])..Date.parse(dates[1])
      else
        # Default to last 30 days
        30.days.ago.beginning_of_day..Time.current
      end
    end
  end
end
