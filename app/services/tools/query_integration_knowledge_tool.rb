# frozen_string_literal: true

module Tools
  # QueryIntegrationKnowledgeTool
  #
  # Allows Amos and agents to query the integration expert knowledge base
  # before executing integration operations. This supports the "Learn Before Act"
  # principle by providing instant access to integration-specific documentation.
  #
  # Usage:
  #   - Before executing QuickBooks operations, query for correct syntax
  #   - Learn about rate limits, error handling, and best practices
  #   - Understand API-specific quirks (e.g., QB Query Language vs REST)
  #
  class QueryIntegrationKnowledgeTool < BaseTool
    TOOL_NAME = 'query_integration_knowledge'

    def self.metadata
      {
        name: TOOL_NAME,
        description: <<~DESC.strip,
          Query the integration expert knowledge base to learn how to properly use 
          an integration's API. Use this BEFORE executing unfamiliar operations to 
          understand correct parameters, query syntax, and common pitfalls.
          
          Examples of when to use:
          - "How do I list open invoices in QuickBooks?"
          - "What's the correct format for Stripe date filters?"
          - "How do I paginate results in Stripe?"
          
          This tool embodies the "Learn Before Act" principle - verify your approach 
          before executing operations that might fail.
        DESC
        category: "integration",
        input_schema: {
          type: "object",
          properties: {
            question: {
              type: "string",
              description: "The question about how to use an integration (e.g., 'How do I filter QuickBooks invoices by status?')"
            },
            integration_name: {
              type: "string",
              description: "Optional: Filter to a specific integration (e.g., 'quickbooks', 'stripe', 'gmail'). If omitted, searches all integrations."
            },
            top_k: {
              type: "integer",
              description: "Number of relevant knowledge chunks to return (default: 3)",
              default: 3
            }
          },
          required: ["question"]
        }
      }
    end

    def self.read_only?
      true # This tool only reads, doesn't modify state
    end

    def execute(args)
      question = get_arg(args, :question)
      integration_name = get_arg(args, :integration_name)
      top_k = get_arg(args, :top_k, 3)

      return error_response('question is required') if question.blank?

      log_execution(args)

      # Try RAG-based search first
      results = query_rag_knowledge(question, integration_name, top_k)

      if results.empty?
        # No RAG results - try to provide inline knowledge
        inline_knowledge = get_inline_knowledge(question, integration_name)
        
        if inline_knowledge
          return success_response({
            source: 'inline_knowledge',
            integration: integration_name || 'general',
            knowledge: inline_knowledge,
            message: "Based on built-in integration knowledge:"
          })
        else
          return success_response({
            source: 'no_results',
            message: "No specific documentation found for this question. Consider: " \
                     "1) Checking list_operations() for available parameters, " \
                     "2) Trying the operation and reading error messages, " \
                     "3) Consulting the integration's official documentation.",
            suggestion: "You can also use find_best_agent to find a specialist for this integration."
          })
        end
      end

      # Format results for LLM consumption
      formatted_results = results.map do |result|
        {
          integration: result[:integration],
          section: result[:section],
          content: result[:content]
        }
      end

      success_response({
        source: 'integration_knowledge_base',
        results_count: formatted_results.size,
        results: formatted_results,
        message: "Found #{formatted_results.size} relevant knowledge sections:"
      })
    end

    private

    def query_rag_knowledge(question, integration_name, top_k)
      service = IntegrationKnowledgeLoaderService.new
      service.query_integration_knowledge(
        question,
        integration_name: integration_name,
        top_k: top_k
      )
    rescue => e
      Rails.logger.warn "[QueryIntegrationKnowledge] RAG query failed: #{e.message}"
      []
    end

    def get_inline_knowledge(question, integration_name)
      # Provide quick inline answers for common questions
      # This is a fallback when RAG isn't available
      
      case integration_name&.downcase
      when 'quickbooks'
        quickbooks_inline_knowledge(question)
      when 'stripe'
        stripe_inline_knowledge(question)
      else
        # Try to match from question if no integration specified
        if question.downcase.include?('quickbooks') || question.downcase.include?('qbo')
          quickbooks_inline_knowledge(question)
        elsif question.downcase.include?('stripe')
          stripe_inline_knowledge(question)
        else
          nil
        end
      end
    end

    def quickbooks_inline_knowledge(question)
      question_lower = question.downcase
      
      if question_lower.include?('open') && question_lower.include?('invoice')
        return <<~KNOWLEDGE
          **QuickBooks: Listing Open Invoices**
          
          QuickBooks uses SQL-like Query Language. Open invoices have Balance > 0.
          
          Correct approach:
          ```
          execute_integration(
            connection_id: xxx,
            operation_id: "quickbooks.list_invoices",
            params: { query: "SELECT * FROM Invoice WHERE Balance > '0'" }
          )
          ```
          
          Note: Use the `query` parameter with SQL-like syntax, NOT `status: "Open"`.
        KNOWLEDGE
      end
      
      if question_lower.include?('paid') && question_lower.include?('invoice')
        return <<~KNOWLEDGE
          **QuickBooks: Listing Paid Invoices**
          
          Paid invoices have Balance = 0.
          
          Correct approach:
          ```
          execute_integration(
            connection_id: xxx,
            operation_id: "quickbooks.list_invoices",
            params: { query: "SELECT * FROM Invoice WHERE Balance = '0'" }
          )
          ```
        KNOWLEDGE
      end
      
      if question_lower.include?('query') || question_lower.include?('select') || question_lower.include?('syntax')
        return <<~KNOWLEDGE
          **QuickBooks Query Language (QBL)**
          
          QuickBooks uses SQL-like queries instead of REST parameters for listings.
          
          Syntax: SELECT * FROM EntityName WHERE condition MAXRESULTS n
          
          Common queries:
          - All invoices: SELECT * FROM Invoice
          - Open invoices: SELECT * FROM Invoice WHERE Balance > '0'
          - Customers: SELECT * FROM Customer WHERE Active = true
          - Date filter: SELECT * FROM Invoice WHERE TxnDate >= '2024-01-01'
          
          Entity names are case-sensitive (Invoice, not invoice).
          Values must be in single quotes.
        KNOWLEDGE
      end
      
      if question_lower.include?('customer')
        return <<~KNOWLEDGE
          **QuickBooks: Listing Customers**
          
          Use the Query API with SQL-like syntax:
          
          ```
          execute_integration(
            connection_id: xxx,
            operation_id: "quickbooks.list_customers",
            params: { query: "SELECT * FROM Customer MAXRESULTS 100" }
          )
          ```
          
          Filters:
          - Active only: WHERE Active = true
          - By name: WHERE DisplayName LIKE '%Smith%'
        KNOWLEDGE
      end
      
      nil
    end

    def stripe_inline_knowledge(question)
      question_lower = question.downcase
      
      if question_lower.include?('date') || question_lower.include?('filter') || question_lower.include?('timestamp')
        return <<~KNOWLEDGE
          **Stripe: Date Filtering**
          
          Stripe uses Unix timestamps with nested parameters:
          
          ```
          params: {
            "created[gte]": 1704067200,  // After this timestamp
            "created[lte]": 1706745600   // Before this timestamp
          }
          ```
          
          Keys: gt (>), gte (>=), lt (<), lte (<=)
          Timestamps are in seconds since Unix epoch.
        KNOWLEDGE
      end
      
      if question_lower.include?('pagination') || question_lower.include?('page') || question_lower.include?('next')
        return <<~KNOWLEDGE
          **Stripe: Pagination**
          
          Stripe uses cursor-based pagination with `starting_after`:
          
          ```
          params: {
            limit: 10,
            starting_after: "cus_xxx"  // ID of last object from previous page
          }
          ```
          
          Use the `id` of the last object in the response for the next page.
          Check `has_more` in the response to know if more data exists.
        KNOWLEDGE
      end
      
      if question_lower.include?('invoice') && question_lower.include?('open')
        return <<~KNOWLEDGE
          **Stripe: Open Invoices**
          
          Use the status parameter:
          
          ```
          execute_integration(
            connection_id: xxx,
            operation_id: "stripe.list_invoices",
            params: { status: "open", limit: 50 }
          )
          ```
          
          Status values: draft, open, paid, uncollectible, void
        KNOWLEDGE
      end
      
      if question_lower.include?('customer')
        return <<~KNOWLEDGE
          **Stripe: Listing Customers**
          
          ```
          execute_integration(
            connection_id: xxx,
            operation_id: "stripe.list_customers",
            params: { limit: 100 }
          )
          ```
          
          Filters available:
          - email: Filter by exact email
          - created[gte]/created[lte]: Date range
          - starting_after: Pagination cursor
        KNOWLEDGE
      end
      
      nil
    end
  end
end
