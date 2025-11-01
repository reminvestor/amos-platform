# AWS Comprehend NLP Enhancement Guide

## Overview

AWS Comprehend is a natural language processing (NLP) service that uses machine learning to extract insights from text. In the AMOS platform, Comprehend enhances the RAG (Retrieval-Augmented Generation) system by:

1. **Document Analysis**: Extracting entities, key phrases, sentiment, and language from uploaded documents
2. **Query Enhancement**: Analyzing user queries to improve search accuracy
3. **Content Understanding**: Detecting PII, sentiment, and other linguistic features

## Architecture

### Integration Points

```
Document Upload → OCR/Text Extraction → Comprehend Analysis → RAG Storage → Vector DB
                                         ↓
                                    Store NLP metadata

User Query → Comprehend Query Analysis → Enhanced Search Terms → Hybrid Search
                ↓
           Entities + Key Phrases
```

### Components

1. **Aws::ComprehendService** (`app/services/aws/comprehend_service.rb`)
   - Singleton service wrapping AWS Comprehend API
   - Handles all NLP operations
   - Tracks usage costs per entity

2. **DocumentProcessorV2** (`app/services/document_processor_v2.rb`)
   - Integrates Comprehend into document processing pipeline
   - Stores NLP insights in RAG document metadata

3. **HybridRagQueryService** (`app/services/hybrid_rag_query_service.rb`)
   - Uses Comprehend to analyze user queries
   - Expands search terms with extracted entities and phrases

## Features

### 1. Entity Detection

Identifies named entities in text:
- **PERSON**: People's names
- **ORGANIZATION**: Company/organization names
- **LOCATION**: Geographic locations
- **DATE**: Temporal expressions
- **QUANTITY**: Numerical values
- **EVENT**: Named events
- **TITLE**: Job titles, honorifics
- **COMMERCIAL_ITEM**: Products, services
- **OTHER**: Miscellaneous entities

**Example**:
```ruby
service = Aws::ComprehendService.instance
result = service.detect_entities(
  "Apple CEO Tim Cook announced the iPhone 15 in Cupertino",
  entity: current_entity
)

# Result:
# [
#   { type: "ORGANIZATION", text: "Apple", score: 0.99 },
#   { type: "PERSON", text: "Tim Cook", score: 0.98 },
#   { type: "COMMERCIAL_ITEM", text: "iPhone 15", score: 0.95 },
#   { type: "LOCATION", text: "Cupertino", score: 0.97 }
# ]
```

### 2. Key Phrase Extraction

Extracts important phrases that capture the main topics:

```ruby
result = service.extract_key_phrases(
  "The new marketing campaign will focus on digital channels and social media engagement",
  entity: current_entity
)

# Result:
# [
#   { text: "new marketing campaign", score: 0.99 },
#   { text: "digital channels", score: 0.95 },
#   { text: "social media engagement", score: 0.93 }
# ]
```

### 3. Sentiment Analysis

Determines the emotional tone of text:

```ruby
result = service.analyze_sentiment(
  "We're thrilled with the outstanding results from our latest product launch!",
  entity: current_entity
)

# Result:
# {
#   sentiment: :positive,
#   scores: {
#     positive: 0.98,
#     negative: 0.01,
#     neutral: 0.01,
#     mixed: 0.00
#   }
# }
```

### 4. Language Detection

Identifies the language of text:

```ruby
result = service.detect_language("Bonjour, comment allez-vous?")

# Result:
# {
#   success: true,
#   language_code: 'fr',
#   primary_language: { language_code: 'fr', score: 0.99 }
# }
```

### 5. PII Detection

Identifies personally identifiable information for compliance:

```ruby
result = service.detect_pii(
  "Contact me at john.doe@example.com or call 555-123-4567",
  entity: current_entity
)

# Result:
# {
#   entities: [
#     { type: "EMAIL", score: 0.99 },
#     { type: "PHONE", score: 0.95 }
#   ],
#   contains_pii: true
# }
```

### 6. Syntax Analysis

Tokenizes text and identifies parts of speech:

```ruby
result = service.detect_syntax("The quick brown fox jumps", entity: current_entity)

# Result includes tokens with part-of-speech tags:
# DET (The), ADJ (quick), ADJ (brown), NOUN (fox), VERB (jumps)
```

## Document Processing Integration

### Automatic NLP Analysis

When documents are uploaded, Comprehend automatically analyzes them:

```ruby
processor = DocumentProcessorV2.instance
result = processor.process_document(entity, file_path, {
  enable_nlp: true,          # Enable Comprehend analysis
  detect_entities: true,     # Extract entities
  detect_key_phrases: true,  # Extract key phrases
  detect_sentiment: true,    # Analyze sentiment
  detect_pii: true           # Detect PII (optional)
})

# NLP insights are stored in RAG document metadata:
# {
#   language: 'en',
#   entities: [...],
#   key_phrases: [...],
#   sentiment: :neutral,
#   pii_entities: [...]
# }
```

### Storage

NLP insights are stored in multiple places:

1. **RagDocument.metadata** (JSONB column)
   - Complete NLP analysis results
   - Accessible for querying and analytics

2. **RagDocument.comprehend_analysis** (JSONB column)
   - Dedicated column for Comprehend results
   - Used for filtering and search

3. **Bedrock Knowledge Base metadata**
   - Top entities and key phrases attached to documents
   - Improves KB search accuracy

## Query Enhancement

### How It Works

When users search the knowledge base, Comprehend enhances their queries:

```ruby
service = HybridRagQueryService.new(entity)
result = service.query(
  "How do I create a marketing campaign for Apple products?",
  enable_nlp: true  # Enable Comprehend query analysis
)

# Query analysis extracts:
# - Entities: ["Apple"]
# - Key phrases: ["marketing campaign", "Apple products"]
# - Enhanced search: "How do I create a marketing campaign for Apple products? Apple marketing campaign Apple products"
```

### Benefits

1. **Better Recall**: Finds documents mentioning "Apple" even if query phrasing differs
2. **Semantic Understanding**: Recognizes "campaign" and "marketing campaign" as related
3. **Multi-lingual Support**: Auto-detects query language
4. **Entity-focused Search**: Prioritizes documents with matching entities

### Example Query Flow

```
Original Query: "Tell me about Tim Cook's presentation at WWDC"
                ↓
Comprehend Analysis:
  - Entities: ["Tim Cook", "WWDC"]
  - Key phrases: ["Tim Cook's presentation"]
                ↓
Enhanced Query: "Tell me about Tim Cook's presentation at WWDC Tim Cook WWDC presentation"
                ↓
Search Results: Finds documents mentioning:
  - Tim Cook speeches
  - WWDC events
  - Apple presentations
```

## Configuration

### Environment Variables

```bash
# AWS credentials (required)
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1

# Enable/disable Comprehend (optional)
AWS_COMPREHEND_ENABLED=true  # default: true
```

### Entity-Level Settings

Comprehend can be enabled/disabled per entity:

```ruby
entity.update!(
  enable_comprehend_analysis: true  # Future enhancement
)
```

### Cost Control

Comprehend tracks usage per entity via `EntityCostTracker`:

```ruby
tracker = EntityCostTracker.new(entity)

# Comprehend pricing:
# - Entity detection: $0.0001 per 100 chars
# - Key phrases: $0.0001 per 100 chars
# - Sentiment: $0.0001 per 100 chars
# - Language detection: $0.0001 per 100 chars
# - PII detection: $0.0001 per 100 chars

# Example cost for 10,000 character document:
# - 100 units × $0.0001 = $0.01 per operation
# - 5 operations (entities, phrases, sentiment, language, PII) = $0.05 total
```

## Usage Examples

### 1. Analyze a Document

```ruby
service = Aws::ComprehendService.instance
analysis = service.analyze_text(
  document_content,
  entity: current_entity,
  operations: [:entities, :sentiment, :key_phrases, :language]
)

puts "Language: #{analysis[:language][:primary_language][:language_code]}"
puts "Sentiment: #{analysis[:sentiment][:sentiment]}"
puts "Top entities: #{analysis[:entities][:entities].first(5).map { |e| e[:text] }}"
puts "Key phrases: #{analysis[:key_phrases][:top_phrases].map { |p| p[:text] }}"
```

### 2. Batch Analyze Multiple Documents

```ruby
service = Aws::ComprehendService.instance
texts = [doc1_content, doc2_content, doc3_content]

batch_result = service.batch_analyze(
  texts,
  entity: current_entity,
  operations: [:entities, :key_phrases]
)

# Process results
batch_result[:results].each_with_index do |result, index|
  puts "Document #{index + 1}: #{result[:entities][:entity_count]} entities found"
end
```

### 3. Analyze Scout Conversation

```ruby
service = Aws::ComprehendService.instance
messages = scout_conversation.messages.map { |m|
  { role: m.role, content: m.content }
}

conversation_analysis = service.analyze_conversation(messages, entity)

puts "Overall sentiment: #{conversation_analysis[:conversation_sentiment][:sentiment]}"
puts "Customer intent: #{conversation_analysis[:customer_intent]}"
puts "Issues detected: #{conversation_analysis[:issues_detected].map { |i| i[:type] }}"
```

### 4. Enhanced RAG Query

```ruby
# Automatic Comprehend enhancement
service = HybridRagQueryService.new(entity)
result = service.query(
  "What are the benefits of our premium plan?",
  enable_nlp: true,  # Enable Comprehend analysis
  top_k: 10
)

puts "Query analysis:"
puts "  Language: #{result[:query_analysis][:language]}"
puts "  Entities: #{result[:query_analysis][:entities].map { |e| e[:text] }}"
puts "  Key phrases: #{result[:query_analysis][:key_phrases].map { |p| p[:text] }}"
puts "  Found #{result[:source_count]} relevant chunks"
```

### 5. PII Redaction

```ruby
service = Aws::ComprehendService.instance
result = service.redact_pii(
  "My email is john@example.com and SSN is 123-45-6789"
)

puts result[:redacted_text]
# Output: "My email is [EMAIL] and SSN is [US_SSN]"

puts result[:pii_entities]
# [
#   { type: "EMAIL", score: 0.99 },
#   { type: "US_SSN", score: 0.98 }
# ]
```

## Performance Considerations

### Text Size Limits

Comprehend has different size limits per operation:

| Operation | Max Size |
|-----------|----------|
| Entity Detection | 100 KB |
| Sentiment Analysis | 5 KB |
| Key Phrase Extraction | 100 KB |
| Syntax Detection | 100 KB |
| PII Detection | 100 KB |
| Language Detection | 5 KB |

The service automatically truncates text to fit these limits.

### Latency

Typical response times:
- Single operation: 50-200ms
- Multi-operation analysis: 200-500ms
- Batch processing: 500-2000ms

### Optimization Tips

1. **Cache query analysis**: Similar queries don't need re-analysis
2. **Batch processing**: Process multiple documents together
3. **Selective operations**: Only run needed analyses
4. **Async processing**: Use background jobs for large documents

```ruby
# Good: Selective operations
service.analyze_text(text, operations: [:entities, :key_phrases])

# Better: Cache results
cache_key = "comprehend:#{Digest::SHA256.hexdigest(text)}"
analysis = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
  service.analyze_text(text)
end
```

## Cost Optimization

### 1. Batch Operations

Process multiple texts in one call:

```ruby
# Instead of this (5 separate API calls):
texts.each { |text| service.detect_entities(text) }

# Do this (1 batch call):
service.batch_analyze(texts, operations: [:entities])
```

### 2. Selective Analysis

Only run needed operations:

```ruby
# For document indexing: entities + key phrases only
service.analyze_text(text, operations: [:entities, :key_phrases])

# For user queries: just entities
service.detect_entities(query_text)

# For sentiment monitoring: sentiment only
service.analyze_sentiment(text)
```

### 3. Text Truncation

Process only relevant portions:

```ruby
# First 10,000 characters for entity detection
preview_text = full_text[0..10_000]
service.detect_entities(preview_text)
```

### 4. Conditional Processing

Skip analysis for certain content types:

```ruby
# Skip NLP for code files
unless file_path.end_with?('.rb', '.js', '.py')
  analysis = service.analyze_text(content)
end
```

## Monitoring and Analytics

### Usage Tracking

All Comprehend operations are tracked via `EntityCostTracker`:

```ruby
# View entity's Comprehend usage
entity.cost_trackers
  .where(service: :comprehend)
  .group(:usage_type)
  .sum(:quantity)

# Output:
# {
#   detect_entities: 15000,    # 15,000 units (1.5M characters)
#   detect_key_phrases: 12000,
#   detect_sentiment: 8000
# }
```

### Cost Reporting

```ruby
# Total Comprehend costs for entity
total_cost = entity.cost_trackers
  .where(service: :comprehend)
  .where('created_at > ?', 30.days.ago)
  .sum("(metadata->>'cost_usd')::float")

puts "Comprehend costs (last 30 days): $#{total_cost.round(2)}"
```

## Troubleshooting

### Common Issues

**1. "Comprehend API rate limit exceeded"**

Solution: Add delays between requests
```ruby
texts.each_with_index do |text, i|
  service.analyze_text(text)
  sleep(0.1) if i % 20 == 0  # Pause every 20 requests
end
```

**2. "Text too long" errors**

Solution: Service auto-truncates, but verify:
```ruby
if text.bytesize > 100_000
  text = text.byteslice(0, 100_000)
end
```

**3. "Unsupported language" errors**

Solution: Check language support
```ruby
language = service.detect_language(text)[:language_code]

if Aws::ComprehendService::SUPPORTED_LANGUAGES.include?(language)
  service.detect_entities(text, language_code: language)
else
  # Fallback to English
  service.detect_entities(text, language_code: 'en')
end
```

## Testing

### Unit Tests

```ruby
# test/services/aws/comprehend_service_test.rb
test "detects entities in text" do
  service = Aws::ComprehendService.instance

  result = service.detect_entities(
    "Apple CEO Tim Cook spoke at WWDC",
    entity: entities(:demo_company)
  )

  assert result[:success]
  assert_equal 3, result[:entity_count]

  org = result[:entities_by_type]['ORGANIZATION'].first
  assert_equal "Apple", org[:text]
end
```

### Integration Tests

```ruby
# test/integration/comprehend_rag_integration_test.rb
test "query analysis enhances search results" do
  # Upload document mentioning "Apple"
  upload_document("Apple product launch announcement.pdf")

  # Query without entity name
  result = HybridRagQueryService.new(@entity).query(
    "What did the CEO announce?",
    enable_nlp: true
  )

  # Should still find Apple document
  assert result[:chunks].any? { |c| c[:content].include?("Apple") }

  # Check query analysis ran
  assert_not_nil result[:query_analysis]
  assert result[:query_analysis][:entities].any?
end
```

## Best Practices

1. **Enable for Production Data**: Use Comprehend on real user content for maximum benefit
2. **Monitor Costs**: Set up alerts for unexpected cost increases
3. **Cache Results**: Cache entity/phrase extraction for frequently accessed documents
4. **Selective Processing**: Not every document needs full NLP analysis
5. **Privacy Compliance**: Use PII detection to identify sensitive content
6. **Multi-lingual Support**: Let Comprehend auto-detect language rather than assuming English
7. **Error Handling**: Always wrap Comprehend calls in try-catch blocks
8. **Background Processing**: Run analysis asynchronously for large documents

## Future Enhancements

### Planned Features

1. **Custom Entity Recognition**: Train custom models for domain-specific entities
2. **Topic Modeling**: Automatic categorization of documents
3. **Relationship Extraction**: Identify connections between entities
4. **Summarization**: Generate automatic document summaries
5. **Events Detection**: Track temporal events mentioned in text
6. **Targeted Sentiment**: Sentiment analysis per entity mentioned

### Roadmap

- **Phase 3.1**: Custom classifiers for campaign classification
- **Phase 3.2**: Entity relationship graphs
- **Phase 3.3**: Multi-document summarization
- **Phase 3.4**: Real-time sentiment dashboards

## References

- [AWS Comprehend Documentation](https://docs.aws.amazon.com/comprehend/)
- [Comprehend Pricing](https://aws.amazon.com/comprehend/pricing/)
- [Entity Types Reference](https://docs.aws.amazon.com/comprehend/latest/dg/how-entities.html)
- [Language Support](https://docs.aws.amazon.com/comprehend/latest/dg/supported-languages.html)
