# frozen_string_literal: true

# GlobalKnowledgeArchive - Preserved knowledge from agents
#
# When agents retire or discover important insights, their knowledge
# is preserved in this archive for future agents to learn from.
#
# This creates institutional memory that persists beyond individual agents.
#
# Knowledge Types:
# - technique: Methods or approaches that work well
# - pattern: Recognized patterns in data or behavior
# - prompt_template: Effective prompt structures
# - tool_usage: Tips for using specific tools
# - domain_expertise: Specialized domain knowledge
#
class GlobalKnowledgeArchive < ApplicationRecord
  belongs_to :entity

  KNOWLEDGE_TYPES = %w[technique pattern prompt_template tool_usage domain_expertise lesson_learned].freeze
  SOURCE_TYPES = %w[agent_retirement manual_archive knowledge_graduation evolution_learning agent_discovery].freeze

  validates :title, presence: true
  validates :knowledge_type, inclusion: { in: KNOWLEDGE_TYPES }, allow_nil: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true

  scope :by_type, ->(type) { where(knowledge_type: type) }
  scope :by_source, ->(source) { where(source_type: source) }
  scope :from_agent, ->(slug) { where(source_agent_slug: slug) }
  scope :applicable_to_domain, ->(domain) { where("applicable_domains @> ?", [domain].to_json) }
  scope :applicable_to_capability, ->(cap) { where("applicable_capabilities @> ?", [cap].to_json) }
  scope :high_utility, -> { where('utility_score >= ?', 0.7) }
  scope :recent, -> { order(created_at: :desc) }
  scope :most_accessed, -> { order(times_accessed: :desc) }
  scope :most_applied, -> { order(times_applied: :desc) }

  # ═══════════════════════════════════════════════════════════════════════════
  # ACCESS TRACKING
  # ═══════════════════════════════════════════════════════════════════════════

  def record_access!
    increment!(:times_accessed)
    update!(last_accessed_at: Time.current)
  end

  def record_application!
    increment!(:times_applied)
    
    # Boost utility score when knowledge is actually used
    if times_applied > 5 && utility_score.to_f < 0.9
      new_score = [utility_score.to_f + 0.05, 1.0].min
      update!(utility_score: new_score)
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # RELEVANCE
  # ═══════════════════════════════════════════════════════════════════════════

  def relevant_to_agent?(agent)
    return true if applicable_domains.blank? && applicable_capabilities.blank?
    
    # Check domain overlap
    if applicable_domains.present?
      agent_domains = agent.metadata&.dig('domains') || []
      return true if (applicable_domains & agent_domains).any?
    end
    
    # Check capability overlap
    if applicable_capabilities.present?
      agent_caps = agent.capabilities_definition&.dig('capabilities') || []
      return true if (applicable_capabilities & agent_caps).any?
    end
    
    false
  end

  def relevance_score_for(agent)
    return 0.5 if applicable_domains.blank? && applicable_capabilities.blank?
    
    score = 0.0
    total_factors = 0
    
    if applicable_domains.present?
      agent_domains = agent.metadata&.dig('domains') || []
      overlap = (applicable_domains & agent_domains).count
      score += overlap.to_f / applicable_domains.count if applicable_domains.any?
      total_factors += 1
    end
    
    if applicable_capabilities.present?
      agent_caps = agent.capabilities_definition&.dig('capabilities') || []
      overlap = (applicable_capabilities & agent_caps).count
      score += overlap.to_f / applicable_capabilities.count if applicable_capabilities.any?
      total_factors += 1
    end
    
    total_factors > 0 ? (score / total_factors) : 0.5
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # SUMMARY
  # ═══════════════════════════════════════════════════════════════════════════

  def summary
    {
      title: title,
      knowledge_type: knowledge_type,
      source_agent: source_agent_name,
      utility_score: utility_score,
      times_used: times_applied,
      applicable_domains: applicable_domains
    }
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  class << self
    # Archive knowledge from a retiring agent
    def preserve_from_agent(agent)
      return [] unless agent.respond_to?(:search_knowledge)
      
      archived = []
      
      # Get agent's knowledge base content
      knowledge_items = agent.search_knowledge("*", limit: 100) rescue []
      
      knowledge_items.each do |item|
        archive = create!(
          entity: agent.entity,
          source_agent_slug: agent.slug,
          source_agent_name: agent.name,
          source_type: 'agent_retirement',
          title: item[:title] || "Knowledge from #{agent.name}",
          content: item[:content],
          knowledge_type: infer_knowledge_type(item),
          applicable_domains: agent.metadata&.dig('domains') || [],
          applicable_capabilities: agent.capabilities_definition&.dig('capabilities') || [],
          utility_score: item[:metadata]&.dig('utility_score') || 0.5,
          metadata: item[:metadata] || {}
        )
        archived << archive
      end
      
      archived
    end

    # Find knowledge relevant to a task
    def search_for_task(entity:, task_description:, limit: 5)
      # Simple keyword-based search for now
      # In production, use vector similarity search
      keywords = task_description.downcase.split(/\W+/).reject { |w| w.length < 4 }
      
      return [] if keywords.empty?
      
      # Build search query
      conditions = keywords.map { |k| "LOWER(title || ' ' || COALESCE(content, '')) LIKE ?" }
      values = keywords.map { |k| "%#{k}%" }
      
      where(entity: entity)
        .where(conditions.join(' OR '), *values)
        .high_utility
        .order(utility_score: :desc, times_applied: :desc)
        .limit(limit)
    end

    # Archive a learning from evolution
    def archive_learning(entity:, title:, content:, source_agent: nil, knowledge_type: 'lesson_learned', metadata: {})
      create!(
        entity: entity,
        source_agent_slug: source_agent&.slug,
        source_agent_name: source_agent&.name,
        source_type: 'evolution_learning',
        title: title,
        content: content,
        knowledge_type: knowledge_type,
        utility_score: 0.6,
        metadata: metadata
      )
    end

    private

    def infer_knowledge_type(item)
      content = (item[:content] || '').downcase
      
      if content.include?('prompt') || content.include?('template')
        'prompt_template'
      elsif content.include?('tool') || content.include?('function')
        'tool_usage'
      elsif content.include?('pattern') || content.include?('common')
        'pattern'
      elsif content.include?('technique') || content.include?('method')
        'technique'
      else
        'domain_expertise'
      end
    end
  end
end


