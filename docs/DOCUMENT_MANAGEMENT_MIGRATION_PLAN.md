# Document Management System Migration Plan

## Overview

This plan outlines how to migrate from the current basic document store to a full Document Management System with subject organization, advanced search, and analytics capabilities.

## Current State Analysis

### What We Have
1. **RagDocument Model**: Basic document storage with S3 integration
2. **Document Processing Pipeline**: Docling → Chunking → Embeddings → Pinecone
3. **Basic Document UI**: Upload and list at `/documents`
4. **System Documents**: Category-based organization for admin docs
5. **Multi-tenant RAG**: Entity isolation in Pinecone

### What's Missing
1. No subject/collection organization for entity documents
2. No tagging or metadata management
3. Limited search (no filters, no saved searches)
4. No document relationships or versioning
5. No analytics or usage tracking
6. No integration with BI/data lake

## Migration Phases

### Phase 1: Database Foundation (Week 1)

#### 1.1 Create Core Tables
```bash
# Generate migrations
rails generate migration CreateDocumentSubjects
rails generate migration CreateDocumentTags
rails generate migration CreateDocumentAnalytics
rails generate migration EnhanceRagDocuments
```

#### 1.2 Migration Files
```ruby
# db/migrate/xxx_create_document_subjects.rb
class CreateDocumentSubjects < ActiveRecord::Migration[8.0]
  def change
    create_table :document_subjects do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.references :parent, foreign_key: { to_table: :document_subjects }
      t.string :color, limit: 7
      t.string :icon, limit: 50
      t.jsonb :metadata, default: {}
      t.jsonb :rules, default: {} # For smart folders
      t.boolean :is_smart_folder, default: false
      t.timestamps
    end
    
    add_index :document_subjects, [:entity_id, :name, :parent_id], unique: true
    add_index :document_subjects, :is_smart_folder
  end
end

# db/migrate/xxx_create_document_tags.rb
class CreateDocumentTags < ActiveRecord::Migration[8.0]
  def change
    create_table :document_tags do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false, limit: 100
      t.string :category, limit: 50
      t.integer :usage_count, default: 0
      t.timestamps
    end
    
    add_index :document_tags, [:entity_id, :name, :category], unique: true
    add_index :document_tags, :usage_count
    
    # Junction tables
    create_table :document_subject_assignments do |t|
      t.references :rag_document, null: false, foreign_key: true
      t.references :document_subject, null: false, foreign_key: true
      t.references :assigned_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    
    add_index :document_subject_assignments, 
              [:rag_document_id, :document_subject_id], 
              unique: true,
              name: 'idx_doc_subject_unique'
    
    create_table :document_tag_assignments do |t|
      t.references :rag_document, null: false, foreign_key: true
      t.references :document_tag, null: false, foreign_key: true
      t.timestamps
    end
    
    add_index :document_tag_assignments,
              [:rag_document_id, :document_tag_id],
              unique: true,
              name: 'idx_doc_tag_unique'
  end
end

# db/migrate/xxx_enhance_rag_documents.rb
class EnhanceRagDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :rag_documents, :title, :string, limit: 500
    add_column :rag_documents, :summary, :text
    add_column :rag_documents, :author, :string
    add_column :rag_documents, :document_date, :date
    add_column :rag_documents, :language, :string, limit: 10, default: 'en'
    add_column :rag_documents, :ocr_performed, :boolean, default: false
    add_column :rag_documents, :view_count, :integer, default: 0
    add_column :rag_documents, :last_accessed_at, :timestamp
    add_column :rag_documents, :version, :integer, default: 1
    add_column :rag_documents, :parent_document_id, :bigint
    
    add_foreign_key :rag_documents, :rag_documents, column: :parent_document_id
    add_index :rag_documents, :view_count
    add_index :rag_documents, :document_date
  end
end
```

#### 1.3 Create Models
```ruby
# app/models/document_subject.rb
class DocumentSubject < ApplicationRecord
  belongs_to :entity
  belongs_to :parent, class_name: 'DocumentSubject', optional: true
  has_many :children, class_name: 'DocumentSubject', foreign_key: :parent_id
  has_many :document_subject_assignments
  has_many :rag_documents, through: :document_subject_assignments
  
  validates :name, presence: true, uniqueness: { scope: [:entity_id, :parent_id] }
  
  scope :root, -> { where(parent_id: nil) }
  scope :smart_folders, -> { where(is_smart_folder: true) }
  
  def full_path
    ancestors.map(&:name).join(' / ') + ' / ' + name
  end
  
  def ancestors
    parent ? parent.ancestors + [parent] : []
  end
  
  # Smart folder evaluation
  def matches_document?(document)
    return false unless is_smart_folder
    
    # Evaluate rules against document
    # Example: { tags: ['contract'], date_range: 'last_30_days' }
    evaluate_rules(document, rules)
  end
end

# app/models/document_tag.rb
class DocumentTag < ApplicationRecord
  belongs_to :entity
  has_many :document_tag_assignments
  has_many :rag_documents, through: :document_tag_assignments
  
  validates :name, presence: true, uniqueness: { scope: [:entity_id, :category] }
  
  CATEGORIES = %w[topic type status priority custom].freeze
  
  scope :popular, -> { order(usage_count: :desc) }
  scope :by_category, ->(cat) { where(category: cat) }
  
  # Auto-increment usage count
  after_create do
    increment!(:usage_count)
  end
end
```

### Phase 2: Enhanced UI Components (Week 2)

#### 2.1 Update Controllers
```ruby
# app/controllers/documents_controller.rb
class DocumentsController < ApplicationController
  before_action :authenticate_user!
  layout 'customer_admin'
  
  def index
    @subjects = current_entity.document_subjects.includes(:children)
    @tags = current_entity.document_tags.popular.limit(20)
    
    @documents = filter_documents(current_entity.rag_documents)
                 .includes(:document_subjects, :document_tags)
                 .page(params[:page])
    
    # Track popular searches
    if params[:q].present?
      track_search(params[:q])
    end
  end
  
  def show
    @document = current_entity.rag_documents.find(params[:id])
    @document.increment!(:view_count)
    @document.update_column(:last_accessed_at, Time.current)
    
    # Find related documents
    @related = @document.find_similar_documents(limit: 5)
    
    # Load analytics
    @analytics = DocumentAnalytics.for_document(@document)
  end
  
  def create
    @document = DocumentUploadService.new(current_entity).upload(
      file: params[:document][:file],
      metadata: document_params,
      auto_categorize: true
    )
    
    if @document.persisted?
      redirect_to @document, notice: 'Document uploaded successfully'
    else
      render :new
    end
  end
  
  private
  
  def filter_documents(scope)
    scope = scope.joins(:document_subjects).where(document_subjects: { id: params[:subject_id] }) if params[:subject_id]
    scope = scope.joins(:document_tags).where(document_tags: { name: params[:tags] }) if params[:tags]
    scope = scope.where('rag_documents.created_at > ?', parse_date_range(params[:date_range])) if params[:date_range]
    scope = scope.search(params[:q]) if params[:q].present?
    scope
  end
end
```

#### 2.2 Create Services
```ruby
# app/services/document_upload_service.rb
class DocumentUploadService
  def initialize(entity)
    @entity = entity
  end
  
  def upload(file:, metadata: {}, auto_categorize: false)
    ActiveRecord::Base.transaction do
      # Create RagStore if needed
      rag_store = find_or_create_rag_store
      
      # Extract metadata
      extracted = extract_document_metadata(file)
      
      # Save file temporarily
      temp_path = save_temp_file(file)
      
      # Start pipeline
      Rag::DocumentPipelineJob.perform_later(
        rag_store.id,
        temp_path,
        metadata: metadata.merge(extracted)
      )
      
      # Create document record
      document = rag_store.rag_documents.create!(
        original_filename: file.original_filename,
        content_type: file.content_type,
        file_size_bytes: file.size,
        title: metadata[:title] || extracted[:title],
        author: metadata[:author] || extracted[:author],
        document_date: metadata[:date] || extracted[:date],
        summary: metadata[:summary]
      )
      
      # Auto-categorize if requested
      if auto_categorize
        DocumentCategorizationService.new(@entity).categorize(document)
      end
      
      document
    end
  end
  
  private
  
  def extract_document_metadata(file)
    # Use Apache Tika or similar to extract metadata
    {
      title: extract_title(file),
      author: extract_author(file),
      date: extract_date(file),
      language: detect_language(file)
    }
  end
end

# app/services/document_categorization_service.rb
class DocumentCategorizationService
  def initialize(entity)
    @entity = entity
    @ai_client = OpenAI::Client.new(access_token: ENV["OPENAI_API_KEY"])
  end
  
  def categorize(document)
    # Get document content preview
    content = get_content_preview(document)
    
    # Get existing subjects and tags
    subjects = @entity.document_subjects.pluck(:name)
    tags = @entity.document_tags.pluck(:name)
    
    # Use AI to suggest categories
    suggestions = ai_suggest_categories(content, subjects, tags)
    
    # Apply suggestions
    apply_suggestions(document, suggestions)
  end
  
  private
  
  def ai_suggest_categories(content, existing_subjects, existing_tags)
    prompt = build_categorization_prompt(content, existing_subjects, existing_tags)
    
    response = @ai_client.chat(
      parameters: {
        model: "gpt-4",
        messages: [{ role: "system", content: prompt }],
        temperature: 0.3
      }
    )
    
    parse_ai_response(response)
  end
end
```

### Phase 3: Search & Analytics (Week 3)

#### 3.1 Enhanced Search
```ruby
# app/services/document_search_service.rb
class DocumentSearchService
  def initialize(entity)
    @entity = entity
  end
  
  def search(query:, filters: {}, use_ai: false)
    if use_ai
      semantic_search(query, filters)
    else
      keyword_search(query, filters)
    end
  end
  
  private
  
  def semantic_search(query, filters)
    # Get all entity's RAG stores
    rag_stores = @entity.rag_stores.active
    
    # Use HybridRagQueryService for semantic search
    results = HybridRagQueryService.new.query(
      query: query,
      entity: @entity,
      filters: build_pinecone_filters(filters)
    )
    
    # Map back to documents
    document_ids = results[:chunks].map { |c| c[:document_id] }.uniq
    documents = @entity.rag_documents.where(id: document_ids)
    
    # Apply additional filters
    apply_filters(documents, filters)
  end
  
  def keyword_search(query, filters)
    scope = @entity.rag_documents
    
    # Full text search
    if query.present?
      scope = scope.where(
        "to_tsvector('english', title || ' ' || COALESCE(summary, '') || ' ' || original_filename) @@ plainto_tsquery('english', ?)",
        query
      )
    end
    
    apply_filters(scope, filters)
  end
end

# app/models/saved_search.rb
class SavedSearch < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  
  validates :name, presence: true
  validates :query_params, presence: true
  
  scope :alerts_enabled, -> { where(alert_enabled: true) }
  scope :due_for_check, -> { where('last_run_at < ?', 1.day.ago) }
  
  def run
    DocumentSearchService.new(entity).search(
      query: query_params['query'],
      filters: query_params['filters'],
      use_ai: query_params['use_ai']
    )
  end
end
```

#### 3.2 Analytics Tracking
```ruby
# app/jobs/document_analytics_job.rb
class DocumentAnalyticsJob < ApplicationJob
  queue_as :maintenance
  
  def perform
    # Aggregate daily stats
    RagDocument.find_each do |doc|
      stats = calculate_daily_stats(doc)
      
      DocumentAnalytics.upsert({
        rag_document_id: doc.id,
        date: Date.current,
        view_count: stats[:views],
        query_count: stats[:queries],
        relevance_score_avg: stats[:relevance],
        chunk_retrieval_count: stats[:retrievals],
        unique_users: stats[:users]
      }, unique_by: [:rag_document_id, :date])
    end
  end
  
  private
  
  def calculate_daily_stats(document)
    # Aggregate from logs and RAG queries
    {
      views: document.view_count,
      queries: count_ai_queries(document),
      relevance: average_relevance_score(document),
      retrievals: count_chunk_retrievals(document),
      users: count_unique_users(document)
    }
  end
end
```

### Phase 4: Integration & Advanced Features (Week 4)

#### 4.1 Data Lake Integration
```ruby
# app/services/document_data_extraction_service.rb
class DocumentDataExtractionService
  def initialize(document)
    @document = document
  end
  
  def extract_for_bi
    # Extract structured data based on document type
    case @document.content_type
    when /spreadsheet/
      extract_spreadsheet_data
    when /pdf/
      extract_pdf_tables
    when /json/
      extract_json_data
    end
  end
  
  private
  
  def extract_spreadsheet_data
    # Use Roo or similar to parse spreadsheets
    workbook = Roo::Excelx.new(@document.s3_url)
    
    sheets = {}
    workbook.sheets.each do |sheet_name|
      workbook.default_sheet = sheet_name
      sheets[sheet_name] = {
        headers: workbook.row(1),
        data: (2..workbook.last_row).map { |i| workbook.row(i) }
      }
    end
    
    # Send to data lake
    DataLakeIngestion.ingest(
      entity_id: @document.entity_id,
      source: 'document_management',
      data_type: 'spreadsheet',
      data: sheets,
      metadata: {
        document_id: @document.id,
        filename: @document.original_filename
      }
    )
  end
end

# app/models/data_lake_ingestion.rb
class DataLakeIngestion < ApplicationRecord
  def self.ingest(entity_id:, source:, data_type:, data:, metadata: {})
    # Store in analytics-optimized tables
    create!(
      entity_id: entity_id,
      source: source,
      data_type: data_type,
      raw_data: data,
      metadata: metadata,
      ingested_at: Time.current
    )
    
    # Trigger ETL pipeline if needed
    DataLakeEtlJob.perform_later(entity_id, source, data_type)
  end
end
```

## Rollout Strategy

### Phase 1 Rollout (Basic Organization)
1. Deploy database migrations
2. Add subject/tag UI to existing document pages
3. Enable for pilot customers
4. Gather feedback

### Phase 2 Rollout (Enhanced Search)
1. Deploy search enhancements
2. Enable AI search for premium customers
3. Add saved searches
4. Monitor performance

### Phase 3 Rollout (Analytics)
1. Start tracking analytics
2. Deploy dashboard for entity admins
3. Enable knowledge gap reports
4. Add usage alerts

### Phase 4 Rollout (Full DMS)
1. Enable all features
2. Migrate existing documents
3. Train customers
4. Monitor adoption

## Backwards Compatibility

### Existing Documents
- All existing documents continue to work
- Migration job to extract metadata from existing docs
- Gradual enhancement as documents are accessed

### API Compatibility
- Existing RAG queries continue to work
- New features are additive
- Version API endpoints if breaking changes needed

## Performance Considerations

### Database
- Add indexes for all foreign keys
- Partial indexes for filtered queries
- Consider partitioning for large deployments

### Caching
- Cache subject trees per entity
- Cache popular tag clouds
- Cache document metadata

### Background Jobs
- Process document categorization async
- Analytics aggregation in off-hours
- Batch similar operations

## Success Metrics

### Technical Metrics
- Search response time < 200ms
- Document upload time < 30s
- 99.9% uptime for document access

### Business Metrics
- 80% of documents tagged/organized
- 50% reduction in "document not found" queries
- 90% user satisfaction with search

### Usage Metrics
- Average 10+ searches per user per week
- 70% of documents accessed via search
- 30% increase in document uploads
