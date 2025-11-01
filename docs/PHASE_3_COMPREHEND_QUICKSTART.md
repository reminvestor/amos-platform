# Phase 3: AWS Comprehend Quick Start

## What's New in Phase 3

Phase 3 adds **AWS Comprehend NLP enhancement** to the AMOS RAG system, providing:

- 🧠 **Intelligent query analysis**: Extract entities and key phrases from user queries
- 📄 **Document understanding**: Analyze uploaded documents for entities, sentiment, and topics
- 🔍 **Enhanced search**: Automatically expand searches with discovered entities
- 🌍 **Multi-lingual support**: Auto-detect and process 12+ languages
- 🔒 **PII detection**: Identify sensitive information for compliance
- 📊 **Sentiment analysis**: Understand emotional tone of content

## Quick Setup

### 1. Verify AWS Credentials

```bash
# Ensure these are set in .env
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1

# Optional: Enable/disable Comprehend
AWS_COMPREHEND_ENABLED=true  # default: true
```

### 2. Test Comprehend Service

```bash
docker compose exec web rails console
```

```ruby
# Initialize service
service = Aws::ComprehendService.instance

# Test entity detection
result = service.detect_entities(
  "Apple CEO Tim Cook announced new products at WWDC in Cupertino"
)

puts result[:entities].map { |e| "#{e[:type]}: #{e[:text]}" }
# Output:
# ORGANIZATION: Apple
# PERSON: Tim Cook
# EVENT: WWDC
# LOCATION: Cupertino
```

### 3. Enable for Document Processing

Comprehend is **enabled by default** for all document uploads:

```ruby
# Process a document (NLP analysis runs automatically)
processor = DocumentProcessorV2.instance
result = processor.process_document(
  entity,
  "/path/to/document.pdf"
)

# Check NLP insights
puts result[:nlp_insights][:entities].first(5)
puts result[:nlp_insights][:key_phrases].first(5)
puts result[:nlp_insights][:sentiment]
```

### 4. Enable for Query Enhancement

Enhanced query analysis is **opt-in** (performance consideration):

```ruby
# Standard query (no NLP)
service = HybridRagQueryService.new(entity)
result = service.query("How do I create a campaign?")

# Enhanced query (with NLP analysis)
result = service.query(
  "How do I create a campaign?",
  enable_nlp: true  # Analyze query with Comprehend
)

# View query analysis
puts result[:query_analysis][:entities]
puts result[:query_analysis][:key_phrases]
```

## Feature Walkthrough

### Entity Detection

Extracts people, organizations, locations, dates, etc.

```ruby
service = Aws::ComprehendService.instance

text = "Contact Sarah at Microsoft's Seattle office about the Q4 report"

result = service.detect_entities(text, entity: current_entity)

result[:entities_by_type]
# {
#   "PERSON" => [{ text: "Sarah", score: 0.99 }],
#   "ORGANIZATION" => [{ text: "Microsoft", score: 0.98 }],
#   "LOCATION" => [{ text: "Seattle", score: 0.97 }],
#   "DATE" => [{ text: "Q4", score: 0.85 }]
# }
```

### Key Phrase Extraction

Identifies important topics and concepts:

```ruby
text = "Our new marketing strategy will focus on digital transformation and customer engagement"

result = service.detect_key_phrases(text, entity: current_entity)

result[:top_phrases]
# [
#   { text: "new marketing strategy", score: 0.99 },
#   { text: "digital transformation", score: 0.98 },
#   { text: "customer engagement", score: 0.97 }
# ]
```

### Sentiment Analysis

Understand emotional tone:

```ruby
text = "We're extremely disappointed with the recent service outage and poor customer support"

result = service.detect_sentiment(text, entity: current_entity)

result
# {
#   sentiment: :negative,
#   scores: { positive: 0.02, negative: 0.94, neutral: 0.03, mixed: 0.01 },
#   confidence: 0.94
# }
```

### PII Detection

Identify sensitive information:

```ruby
text = "Email me at john.doe@company.com or call my cell at 555-123-4567"

result = service.detect_pii(text, entity: current_entity)

result
# {
#   contains_pii: true,
#   pii_count: 2,
#   pii_types: ["EMAIL", "PHONE"],
#   entities: [
#     { type: "EMAIL", score: 0.99 },
#     { type: "PHONE", score: 0.95 }
#   ]
# }

# Redact PII
redacted = service.redact_pii(text)
puts redacted[:redacted_text]
# "Email me at [EMAIL] or call my cell at [PHONE]"
```

### Language Detection

Auto-detect content language:

```ruby
service.detect_language("Bonjour, comment allez-vous?")
# { language_code: "fr", score: 0.99 }

service.detect_language("¿Cómo estás?")
# { language_code: "es", score: 0.98 }

service.detect_language("How are you?")
# { language_code: "en", score: 0.99 }
```

## Real-World Examples

### Example 1: Enhanced Document Search

**Scenario**: User uploads a PDF about "Apple's Q4 earnings call"

```ruby
# Upload and process document
processor = DocumentProcessorV2.instance
result = processor.process_document(entity, "apple_earnings_q4.pdf")

# Comprehend extracts:
# - Entities: Apple, Tim Cook, Q4, iPhone, Services
# - Key phrases: "quarterly revenue", "services growth", "iPhone sales"
# - Sentiment: :positive

# Later, user searches with different wording
rag_service = HybridRagQueryService.new(entity)
result = rag_service.query(
  "Tell me about the CEO's comments on revenue",
  enable_nlp: true
)

# Comprehend enhances query:
# - Entities: ["revenue"]
# - Key phrases: ["CEO's comments"]
# - Enhanced search: "CEO revenue comments Tim Cook quarterly"

# Result: Finds Apple earnings PDF even though query didn't mention "Apple" or "earnings"
```

### Example 2: Multi-Document Comparison

```ruby
service = Aws::ComprehendService.instance

# Analyze multiple campaign briefs
briefs = [
  "Campaign A: Focus on millennials with social media ads",
  "Campaign B: Target enterprise clients through LinkedIn",
  "Campaign C: Email marketing to existing customer base"
]

results = service.batch_analyze(
  briefs.map.with_index { |text, i| { id: "brief_#{i}", text: text } },
  entity: current_entity
)

# Compare entities across campaigns
results.each do |id, analysis|
  entities = analysis[:entities].map { |e| e[:text] }
  phrases = analysis[:key_phrases].map { |p| p[:text] }

  puts "#{id}: Entities: #{entities.join(', ')}"
  puts "#{id}: Topics: #{phrases.join(', ')}"
end

# Output:
# brief_0: Entities: millennials
# brief_0: Topics: social media ads
# brief_1: Entities: LinkedIn
# brief_1: Topics: enterprise clients
# brief_2: Entities: Email
# brief_2: Topics: existing customer base, email marketing
```

### Example 3: Scout Conversation Analysis

```ruby
service = Aws::ComprehendService.instance

# Analyze Scout conversation for insights
messages = [
  { role: 'user', content: 'I need help creating a marketing campaign' },
  { role: 'assistant', content: 'I can help with that. What product are you promoting?' },
  { role: 'user', content: 'Our new software for project management teams' },
  { role: 'assistant', content: 'Great! Who is your target audience?' },
  { role: 'user', content: 'Small to medium-sized businesses, especially in tech' }
]

analysis = service.analyze_conversation(messages, entity)

puts "Overall sentiment: #{analysis[:conversation_sentiment][:sentiment]}"
# :neutral

puts "Customer intent: #{analysis[:customer_intent]}"
# ["marketing campaign", "new software", "project management teams"]

puts "Key entities: #{analysis[:entities_mentioned]}"
# { "COMMERCIAL_ITEM" => ["software"], "TITLE" => ["project management teams"] }

puts "Language: #{analysis[:language][:language_code]}"
# en
```

## Performance Tips

### 1. Optimize Query Analysis

```ruby
# For high-traffic queries, cache analysis
cache_key = "comprehend_query:#{Digest::SHA256.hexdigest(query)}"
analysis = Rails.cache.fetch(cache_key, expires_in: 1.hour) do
  service = Aws::ComprehendService.instance
  service.analyze_text(query, operations: [:entities, :key_phrases])
end
```

### 2. Batch Process Documents

```ruby
# Instead of processing one-by-one
documents.each { |doc| processor.process_document(entity, doc) }

# Use batch processing
processor.process_batch(entity, document_paths)
```

### 3. Selective Operations

```ruby
# For simple queries, skip NLP
result = rag_service.query("status", enable_nlp: false)

# For complex queries, enable NLP
result = rag_service.query(
  "What did the CEO say about quarterly revenue in the last earnings call?",
  enable_nlp: true
)
```

### 4. Async Processing

```ruby
# For large documents, process in background
ProcessDocumentJob.perform_later(entity.id, file_path, enable_nlp: true)
```

## Cost Monitoring

### Track Usage

```ruby
# View Comprehend usage for entity
tracker = EntityCostTracker.new(entity)

usage = entity.cost_trackers
  .where(service: :comprehend)
  .where('created_at > ?', 30.days.ago)
  .group(:usage_type)
  .sum(:quantity)

puts usage
# {
#   detect_entities: 5000,     # 5,000 units = 500K characters
#   detect_key_phrases: 5000,
#   detect_sentiment: 2000
# }
```

### Estimate Costs

```ruby
# Comprehend pricing (as of 2025):
# $0.0001 per 100 characters (1 unit)

# Example: 100,000 character document
text_length = 100_000
units = (text_length / 100.0).ceil  # 1,000 units

# Cost per operation
cost_per_operation = units * 0.0001  # $0.10

# Total for full analysis (5 operations):
operations = [:entities, :key_phrases, :sentiment, :language, :pii]
total_cost = cost_per_operation * operations.count  # $0.50

puts "Full NLP analysis cost: $#{total_cost}"
```

### Cost Optimization

```ruby
# 1. Analyze only first portion of long documents
preview = full_text[0..50_000]  # First 50K chars
service.analyze_text(preview)

# 2. Skip redundant operations
service.analyze_text(text, operations: [:entities, :key_phrases])  # Skip sentiment/PII

# 3. Cache results for frequently accessed content
cache_key = "comprehend:#{document.file_hash}"
Rails.cache.fetch(cache_key, expires_in: 7.days) do
  service.analyze_text(document.content)
end
```

## Troubleshooting

### Issue: "AWS credentials not configured"

```bash
# Check credentials
docker compose exec web rails console
```

```ruby
Aws.config[:credentials].credentials.access_key_id
# Should return: "AKIA..."

# If nil, update .env and restart
```

### Issue: "Text too long" errors

```ruby
# Service auto-truncates, but you can do it manually:
max_length = Aws::ComprehendService::MAX_TEXT_SIZE[:detect_entities]
safe_text = text.byteslice(0, max_length)
```

### Issue: Query analysis slowing down searches

```ruby
# Disable NLP for simple queries
if query.length < 10 || query.split.count < 3
  result = rag_service.query(query, enable_nlp: false)
else
  result = rag_service.query(query, enable_nlp: true)
end
```

### Issue: High Comprehend costs

```ruby
# 1. Check which operations are running
entity.cost_trackers
  .where(service: :comprehend)
  .group(:usage_type)
  .sum(:quantity)

# 2. Disable operations you don't need
processor.process_document(entity, file, {
  detect_entities: true,
  detect_key_phrases: true,
  detect_sentiment: false,  # Disable if not needed
  detect_pii: false         # Disable if not needed
})

# 3. Set budget alerts
if entity.monthly_comprehend_cost > 100.00
  Rails.logger.warn "Comprehend costs exceeded budget for entity #{entity.id}"
end
```

## Next Steps

1. **Review the comprehensive guide**: See `docs/AWS_COMPREHEND_NLP_GUIDE.md`
2. **Test with real data**: Upload sample documents and analyze results
3. **Enable query enhancement**: Add `enable_nlp: true` to RAG queries
4. **Monitor costs**: Set up alerts for usage spikes
5. **Customize for your domain**: Consider custom entity recognition

## Migration from Phase 2

No migration needed! Phase 3 enhances existing functionality:

- ✅ Documents uploaded in Phase 2 can be re-processed with NLP
- ✅ Bedrock KB continues to work alongside Comprehend
- ✅ pgvector + Pinecone still used for vector search
- ✅ All costs tracked via existing EntityCostTracker

To re-analyze existing documents:

```ruby
# Re-process all entity documents with NLP
processor = DocumentProcessorV2.instance

entity.rag_documents.find_each do |doc|
  next if doc.metadata['nlp_insights'].present?  # Skip if already analyzed

  processor.process_document(
    entity,
    doc.file_path,
    enable_nlp: true
  )
end
```

## Support

- **Documentation**: `docs/AWS_COMPREHEND_NLP_GUIDE.md`
- **AWS Docs**: https://docs.aws.amazon.com/comprehend/
- **Pricing**: https://aws.amazon.com/comprehend/pricing/
- **Status**: https://status.aws.amazon.com/
