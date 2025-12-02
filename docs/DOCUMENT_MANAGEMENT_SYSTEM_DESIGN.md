# Document Management System Design

## Executive Summary

This design enhances the existing RAG system to become a full-featured Document Management System (DMS) with advanced organization, search, and analytics capabilities. The system will support use cases like law firms managing case materials, companies analyzing sales data, and general knowledge base management.

## Key Features

### 1. **Document Organization & Tagging**
- Subject-based collections (e.g., "Q4 Sales Reports", "Patent Law Cases", "Product Documentation")
- Hierarchical tag system with auto-suggestions
- Smart folders with rule-based document organization
- Document relationships and cross-references

### 2. **Advanced Search & Retrieval**
- Multi-faceted search (by tag, date, author, content type, relevance)
- Saved searches and search alerts
- AI-powered semantic search with context understanding
- Document clustering and similarity detection

### 3. **Analytics & Insights**
- Document usage analytics (views, queries, relevance scores)
- Popular topics and trending searches
- Knowledge gap identification
- Query performance metrics

### 4. **Integration with Data Lake/BI**
- Structured data extraction from documents (tables, forms)
- Export to data warehouse for BI analysis
- Automated report generation from document insights
- Integration with existing analytics infrastructure

### 5. **Collaboration Features**
- Document annotations and comments
- Sharing with permission controls
- Version history and change tracking
- Team workspaces

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Document Management UI                         │
│  ┌─────────────┬──────────────┬─────────────┬──────────────┐   │
│  │  Upload &   │   Browse &   │  Search &   │  Analytics   │   │
│  │  Organize   │   Manage     │  Retrieve   │  Dashboard   │   │
│  └─────────────┴──────────────┴─────────────┴──────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────▼─────────────────────────────────┐
│                     Document Management API                        │
│  ┌─────────────┬──────────────┬─────────────┬──────────────┐    │
│  │  Document   │   Subject    │   Search    │  Analytics   │    │
│  │  Service    │   Service    │   Service   │   Service    │    │
│  └─────────────┴──────────────┴─────────────┴──────────────┘    │
└───────────────────────────────────────────────────────────────────┘
                                  │
┌─────────────────────────────────▼─────────────────────────────────┐
│                         Data Layer                                 │
│  ┌─────────────┬──────────────┬─────────────┬──────────────┐    │
│  │  Document   │   Subject    │  Document   │  Analytics   │    │
│  │  Storage    │   Graph      │  Vectors    │  Data Lake   │    │
│  │  (S3)       │  (PostgreSQL)│  (Pinecone) │  (PostgreSQL)│    │
│  └─────────────┴──────────────┴─────────────┴──────────────┘    │
└───────────────────────────────────────────────────────────────────┘
```

## Database Schema Enhancements

### New Tables

```sql
-- Document subjects/collections
CREATE TABLE document_subjects (
  id BIGSERIAL PRIMARY KEY,
  entity_id BIGINT NOT NULL REFERENCES entities(id),
  name VARCHAR(255) NOT NULL,
  description TEXT,
  parent_id BIGINT REFERENCES document_subjects(id),
  color VARCHAR(7), -- hex color for UI
  icon VARCHAR(50), -- lucide icon name
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(entity_id, name, parent_id)
);

-- Document tags
CREATE TABLE document_tags (
  id BIGSERIAL PRIMARY KEY,
  entity_id BIGINT NOT NULL REFERENCES entities(id),
  name VARCHAR(100) NOT NULL,
  category VARCHAR(50), -- 'topic', 'type', 'status', 'custom'
  usage_count INT DEFAULT 0,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(entity_id, name, category)
);

-- Many-to-many: documents to subjects
CREATE TABLE document_subject_assignments (
  id BIGSERIAL PRIMARY KEY,
  rag_document_id BIGINT NOT NULL REFERENCES rag_documents(id),
  document_subject_id BIGINT NOT NULL REFERENCES document_subjects(id),
  assigned_by_id BIGINT REFERENCES users(id),
  created_at TIMESTAMP NOT NULL,
  UNIQUE(rag_document_id, document_subject_id)
);

-- Many-to-many: documents to tags  
CREATE TABLE document_tag_assignments (
  id BIGSERIAL PRIMARY KEY,
  rag_document_id BIGINT NOT NULL REFERENCES rag_documents(id),
  document_tag_id BIGINT NOT NULL REFERENCES document_tags(id),
  created_at TIMESTAMP NOT NULL,
  UNIQUE(rag_document_id, document_tag_id)
);

-- Document relationships
CREATE TABLE document_relationships (
  id BIGSERIAL PRIMARY KEY,
  source_document_id BIGINT NOT NULL REFERENCES rag_documents(id),
  target_document_id BIGINT NOT NULL REFERENCES rag_documents(id),
  relationship_type VARCHAR(50) NOT NULL, -- 'references', 'supersedes', 'related_to'
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMP NOT NULL,
  UNIQUE(source_document_id, target_document_id, relationship_type)
);

-- Document analytics
CREATE TABLE document_analytics (
  id BIGSERIAL PRIMARY KEY,
  rag_document_id BIGINT NOT NULL REFERENCES rag_documents(id),
  date DATE NOT NULL,
  view_count INT DEFAULT 0,
  query_count INT DEFAULT 0,
  relevance_score_avg FLOAT,
  chunk_retrieval_count INT DEFAULT 0,
  unique_users INT DEFAULT 0,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  UNIQUE(rag_document_id, date)
);

-- Saved searches
CREATE TABLE saved_searches (
  id BIGSERIAL PRIMARY KEY,
  entity_id BIGINT NOT NULL REFERENCES entities(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  name VARCHAR(255) NOT NULL,
  query_params JSONB NOT NULL, -- search criteria
  alert_enabled BOOLEAN DEFAULT false,
  alert_frequency VARCHAR(20), -- 'daily', 'weekly', 'monthly'
  last_run_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);

-- Document annotations
CREATE TABLE document_annotations (
  id BIGSERIAL PRIMARY KEY,
  rag_document_id BIGINT NOT NULL REFERENCES rag_documents(id),
  user_id BIGINT NOT NULL REFERENCES users(id),
  page_number INT,
  position JSONB, -- {x, y, width, height} for positioning
  content TEXT NOT NULL,
  annotation_type VARCHAR(20), -- 'note', 'highlight', 'question'
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL
);
```

### Enhanced RagDocument Model

```sql
-- Add columns to existing rag_documents table
ALTER TABLE rag_documents 
ADD COLUMN title VARCHAR(500),
ADD COLUMN summary TEXT,
ADD COLUMN author VARCHAR(255),
ADD COLUMN document_date DATE,
ADD COLUMN language VARCHAR(10) DEFAULT 'en',
ADD COLUMN ocr_performed BOOLEAN DEFAULT false,
ADD COLUMN full_text_search_vector tsvector,
ADD COLUMN view_count INT DEFAULT 0,
ADD COLUMN last_accessed_at TIMESTAMP,
ADD COLUMN version INT DEFAULT 1,
ADD COLUMN parent_document_id BIGINT REFERENCES rag_documents(id);

-- Full text search index
CREATE INDEX idx_rag_documents_fts ON rag_documents USING gin(full_text_search_vector);

-- Trigger to update FTS vector
CREATE OR REPLACE FUNCTION update_document_search_vector() RETURNS trigger AS $$
BEGIN
  NEW.full_text_search_vector := 
    setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.summary, '')), 'B') ||
    setweight(to_tsvector('english', COALESCE(NEW.original_filename, '')), 'C');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_document_search_vector_trigger
BEFORE INSERT OR UPDATE ON rag_documents
FOR EACH ROW EXECUTE FUNCTION update_document_search_vector();
```

## Core Services

### 1. Document Management Service

```ruby
# app/services/document_management_service.rb
class DocumentManagementService
  def initialize(entity)
    @entity = entity
  end
  
  # Upload and organize document
  def upload_document(file, params = {})
    # Create document with metadata
    # Assign to subjects
    # Auto-tag based on content
    # Extract structured data for analytics
  end
  
  # Organize documents
  def assign_to_subject(document_id, subject_id)
    # Assign document to subject/collection
  end
  
  def add_tags(document_id, tag_names)
    # Add tags to document
  end
  
  # Search and retrieve
  def search(query, filters = {})
    # Multi-faceted search combining:
    # - Vector similarity (Pinecone)
    # - Full-text search (PostgreSQL)
    # - Tag/subject filters
    # - Date ranges
  end
  
  # Analytics
  def document_insights(document_id)
    # Usage stats, related documents, popular queries
  end
end
```

### 2. Subject Organization Service

```ruby
# app/services/subject_organization_service.rb
class SubjectOrganizationService
  def initialize(entity)
    @entity = entity
  end
  
  # Create hierarchical subjects
  def create_subject(name, params = {})
    # Create subject/collection
    # Set up smart folder rules if provided
  end
  
  # Auto-organize documents
  def suggest_subjects_for_document(document)
    # Use AI to suggest appropriate subjects
  end
  
  # Smart folders
  def create_smart_folder(name, rules)
    # Create rule-based collection
    # Rules like: { tags: ['contract'], date_range: 'last_30_days' }
  end
end
```

### 3. Analytics & BI Integration Service

```ruby
# app/services/document_analytics_service.rb
class DocumentAnalyticsService
  def initialize(entity)
    @entity = entity
  end
  
  # Extract structured data
  def extract_data_for_bi(document)
    # Extract tables, forms, key-value pairs
    # Send to data lake
  end
  
  # Analytics dashboard data
  def usage_analytics(date_range = 30.days)
    # Document views, searches, popular topics
  end
  
  # Knowledge gaps
  def identify_knowledge_gaps
    # Analyze failed searches
    # Find topics with low document coverage
  end
end
```

## Use Case Examples

### 1. Law Firm - Case Management

```ruby
# Create case subject
case_subject = SubjectOrganizationService.new(law_firm_entity).create_subject(
  "Smith v. Jones Patent Case",
  parent: "Active Cases",
  tags: ["patent", "litigation", "2024"]
)

# Upload case documents
documents = [
  { file: patent_filing, tags: ["patent", "filing"] },
  { file: prior_art_search, tags: ["prior-art", "research"] },
  { file: expert_testimony, tags: ["testimony", "expert-witness"] }
]

documents.each do |doc|
  DocumentManagementService.new(law_firm_entity).upload_document(
    doc[:file],
    subject_ids: [case_subject.id],
    tags: doc[:tags]
  )
end

# Search for relevant precedents
results = DocumentManagementService.new(law_firm_entity).search(
  "patent infringement semiconductor manufacturing",
  filters: {
    tags: ["precedent", "patent"],
    date_range: 5.years.ago..Date.current
  }
)
```

### 2. Sales Analytics - Data Lake Integration

```ruby
# Process sales reports
sales_docs = DocumentManagementService.new(company_entity).search(
  filters: {
    subjects: ["Q4 Sales Reports"],
    content_type: ["spreadsheet", "pdf"]
  }
)

sales_docs.each do |doc|
  # Extract structured data
  data = DocumentAnalyticsService.new(company_entity).extract_data_for_bi(doc)
  
  # Send to data lake for BI analysis
  DataLakeIntegration.ingest(
    source: "document_management",
    entity_id: company_entity.id,
    data: data,
    metadata: {
      document_id: doc.id,
      extraction_date: Date.current
    }
  )
end
```

## Implementation Plan

### Phase 1: Core Document Management (Week 1-2)
1. Database schema updates
2. Document subject/collection system
3. Tagging infrastructure
4. Enhanced document upload with metadata

### Phase 2: Search & Retrieval (Week 3)
1. Multi-faceted search implementation
2. Saved searches
3. Search analytics
4. UI for search and filters

### Phase 3: Analytics & BI Integration (Week 4)
1. Document analytics tracking
2. Structured data extraction
3. Data lake integration
4. Analytics dashboard

### Phase 4: Advanced Features (Week 5-6)
1. Document relationships
2. Annotations and collaboration
3. Version control
4. Smart folders and auto-organization

## Security Considerations

1. **Multi-tenant Isolation**: All queries and operations scoped by entity_id
2. **Permission System**: Document-level permissions for sharing
3. **Audit Trail**: Track all document access and modifications
4. **Encryption**: Documents encrypted at rest in S3
5. **Data Retention**: Configurable retention policies per entity

## Performance Optimization

1. **Caching**: Redis cache for frequent searches and metadata
2. **Background Jobs**: Heavy processing in SolidQueue jobs
3. **Indexes**: Optimized database indexes for search
4. **CDN**: CloudFront for document preview/download
5. **Lazy Loading**: Progressive loading for large document sets

## Success Metrics

1. **Search Performance**: <200ms for 95th percentile searches
2. **Document Processing**: <30s for average document indexing
3. **User Adoption**: 80% of entity users actively using DMS
4. **Knowledge Coverage**: 90% of searches return relevant results
5. **Cost Efficiency**: 50% reduction in manual document management time
