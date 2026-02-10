# frozen_string_literal: true

# Agents::MemoryContext
#
# Provides agents with the same memory capabilities as Scout:
# - User memories (preferences, communication style, past interactions)
# - Business insights (company context, industry knowledge)
# - Agent-specific RAG knowledge base (domain expertise)
#
# This enables agents to be intelligent team members who remember
# context about the user and company, and have deep domain knowledge.
#
# Usage:
#   memory = Agents::MemoryContext.new(
#     agent: agent_plugin,
#     user: current_user,
#     entity: current_entity
#   )
#   context = memory.build_context(task_description)
#
module Agents
  class MemoryContext
    attr_reader :agent, :user, :entity

    def initialize(agent:, user:, entity:)
      @agent = agent
      @user = user
      @entity = entity
    end

    # Build complete memory context for the agent
    # Returns a hash with all memory layers
    def build_context(task_description = nil)
      start_time = Time.current

      context = {
        user_memories: [],
        business_insights: [],
        agent_knowledge: [],
        retrieval_time_ms: 0
      }

      # 1. User memories - what we know about this user
      context[:user_memories] = fetch_user_memories(task_description)

      # 2. Business insights - what we know about the company
      context[:business_insights] = fetch_business_insights

      # 3. Agent-specific knowledge from RAG
      context[:agent_knowledge] = fetch_agent_knowledge(task_description) if task_description.present?

      context[:retrieval_time_ms] = ((Time.current - start_time) * 1000).round

      Rails.logger.info "🧠 Agent memory context built in #{context[:retrieval_time_ms]}ms " \
                        "(#{context[:user_memories].size} user, #{context[:business_insights].size} business, " \
                        "#{context[:agent_knowledge].size} agent knowledge)"

      context
    end

    # Format memory context as text for the system prompt
    def format_for_prompt(context)
      parts = []

      # User context
      if context[:user_memories].any?
        parts << "## What you know about this user:"
        context[:user_memories].each do |memory|
          parts << "- #{memory[:category]}: #{memory[:content]}"
        end
        parts << ""
      end

      # Business context
      if context[:business_insights].any?
        parts << "## Company context:"
        context[:business_insights].each do |insight|
          parts << "- #{insight[:category]}: #{insight[:content]}"
        end
        parts << ""
      end

      # Agent domain knowledge
      if context[:agent_knowledge].any?
        parts << "## Relevant knowledge for this task:"
        context[:agent_knowledge].each do |knowledge|
          parts << "---"
          parts << knowledge[:content].truncate(1000)
        end
        parts << ""
      end

      parts.join("\n")
    end

    private

    # Fetch user memories (preferences, past interactions, etc.)
    def fetch_user_memories(task_description = nil)
      return [] unless defined?(UserMemory) && user && entity

      memories = UserMemory.where(user: user, entity: entity)
                           .where('expires_at IS NULL OR expires_at > ?', Time.current)
                           .where('confidence >= ?', 0.7)
                           .order(access_count: :desc, created_at: :desc)
                           .limit(10)

      memories.map do |m|
        {
          id: m.id,
          category: m.memory_type,
          content: m.content,
          confidence: m.confidence
        }
      end
    rescue => e
      Rails.logger.warn "Could not fetch user memories: #{e.message}"
      []
    end

    # Fetch business insights about the company
    # Pulls from BusinessInsight records AND BusinessProfile for rich context
    def fetch_business_insights
      insights = []
      
      # 1. Get BusinessInsight records if they exist
      if defined?(BusinessInsight) && entity
        bi_records = BusinessInsight.where(entity: entity)
                                    .where('confidence_score >= ?', 0.7)
                                    .order(confidence_score: :desc)
                                    .limit(10) rescue []
        
        insights += bi_records.map do |i|
          {
            id: i.id,
            category: i.insight_type,
            content: i.content,
            confidence: i.confidence_score
          }
        end
      end
      
      # 2. Always include BusinessProfile data - this is the primary source of business context
      biz = BusinessContext.for(user, entity)
      if biz.present?
        ctx = biz.to_h
        insights << { category: 'company', content: "Company Name: #{ctx[:company_name]}" } if ctx[:company_name].present?
        insights << { category: 'industry', content: "Industry: #{ctx[:industry]}" } if ctx[:industry].present?
        insights << { category: 'description', content: "About the business: #{ctx[:description]}" } if ctx[:description].present?
        insights << { category: 'audience', content: "Target Audience: #{ctx[:target_audience]}" } if ctx[:target_audience].present?
        insights << { category: 'tone', content: "Brand voice/tone: #{ctx[:tone_of_voice]}" } if ctx[:tone_of_voice].present?
        insights << { category: 'value_prop', content: "Value Proposition: #{ctx[:value_proposition]}" } if ctx[:value_proposition].present?
        insights << { category: 'services', content: "Services offered: #{ctx[:services]}" } if ctx[:services].present?
        insights << { category: 'mission', content: "Mission: #{ctx[:mission]}" } if ctx[:mission].present?
      elsif entity&.name.present?
        insights << { category: 'company', content: "Company Name: #{entity.name}" }
      end
      
      insights
    rescue => e
      Rails.logger.warn "Could not fetch business insights: #{e.message}"
      []
    end

    # Fetch relevant knowledge from agent's RAG stores
    def fetch_agent_knowledge(task_description)
      return [] unless agent && task_description.present?

      # Get all RAG stores accessible by this agent
      accessible_stores = RagStore.accessible_by_agent(agent, entity).active

      return [] if accessible_stores.empty?

      results = []

      # Query each store for relevant knowledge
      accessible_stores.each do |store|
        chunks = query_rag_store(store, task_description)
        results.concat(chunks)
      end

      # Sort by relevance and limit
      results.sort_by { |r| -r[:similarity] }.take(5)
    rescue => e
      Rails.logger.warn "Could not fetch agent knowledge: #{e.message}"
      []
    end

    # Query a specific RAG store
    def query_rag_store(store, query)
      return [] unless store.ready?

      begin
        # Use the hybrid RAG query service
        # Note: HybridRagQueryService takes entity in constructor and uses .query() method
        service = HybridRagQueryService.new(entity)
        
        # Query returns { chunks: [...], context: ..., ... }
        result = service.query(query, top_k: 3, use_cache: true)
        chunks = result[:chunks] || []

        chunks.map do |chunk|
          {
            store_id: store.id,
            store_name: store.name,
            content: chunk[:content] || chunk['content'],
            similarity: chunk[:similarity_score] || chunk[:combined_score] || 0.5,
            metadata: chunk[:metadata] || {}
          }
        end
      rescue => e
        Rails.logger.warn "RAG query failed for store #{store.id}: #{e.message}"
        []
      end
    end
  end
end
