# Required Environment Variables for App Connection Creation

## AI Services

### OpenAI (Required for embeddings)
```bash
OPENAI_API_KEY=your_openai_api_key
```

### Pinecone (Required for RAG storage)
```bash
PINECONE_API_KEY=your_pinecone_api_key
PINECONE_ENVIRONMENT=your_pinecone_environment  # e.g., "us-east1-gcp"
PINECONE_REGION=us-east-1  # Optional, defaults to us-east-1
```

### Serper API (Optional but recommended for web search)
```bash
SERPER_API_KEY=your_serper_api_key
```
Without this, the system will use mock search results.

## Setup Instructions

1. **OpenAI API Key**
   - Get from: https://platform.openai.com/api-keys
   - Used for: Generating embeddings for RAG store

2. **Pinecone**
   - Sign up at: https://www.pinecone.io/
   - Create an index or let the system create one automatically
   - Get API key from the Pinecone console
   - Note your environment (shown in the console URL)

3. **Serper API**
   - Sign up at: https://serper.dev/
   - Get 2,500 free searches per month
   - Used for: Real web search results for API documentation

## Testing the Setup

Run this in Rails console to verify:

```ruby
# Test Pinecone connection
require 'pinecone'
Pinecone.configure do |config|
  config.api_key = ENV['PINECONE_API_KEY']
  config.environment = ENV['PINECONE_ENVIRONMENT']
end
client = Pinecone::Client.new
puts client.list_indexes

# Test OpenAI
client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
response = client.embeddings(parameters: { model: 'text-embedding-ada-002', input: 'test' })
puts response.dig('data', 0, 'embedding').first(5)

# Test Serper (if configured)
if ENV['SERPER_API_KEY']
  serper = SerperApiService.new
  result = serper.search("Stripe API documentation", num_results: 3)
  puts result
end
```

## Production Considerations

1. **Rate Limits**
   - OpenAI: Monitor embedding API usage
   - Pinecone: Free tier allows 100K vectors
   - Serper: 2,500 searches/month on free tier

2. **Security**
   - Store API keys securely (use Rails credentials in production)
   - Never commit API keys to version control

3. **Costs**
   - OpenAI embeddings: ~$0.0001 per 1K tokens
   - Pinecone: Free tier is generous for development
   - Serper: $50/month for 50K searches after free tier
