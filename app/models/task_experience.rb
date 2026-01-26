# frozen_string_literal: true

# TaskExperience - Learned behaviors from Training-Free GRPO semantic advantage extraction
#
# These are natural language experiences learned by comparing successful vs failed
# task executions. They're injected into prompts to improve future performance.
#
# Philosophy (from Training-Free GRPO paper):
# - LLMs can adapt behavior through context (token priors) without parameter tuning
# - Experiences extracted by comparing "what worked" vs "what didn't work"
# - Multi-epoch learning refines experiences over time
#
# Integration:
# - Created by: SemanticAdvantageService during EvolutionCycleService runs
# - Injected by: GuidanceLibrary.for_task() / DynamicContextService
# - Tracked by: Apply count, utility score, positive outcomes
#
# Example experience:
#   task_type: "integration_setup"
#   content: "Before executing integration actions, always call list_integration_actions 
#             first to verify exact parameter names - APIs often have unexpected requirements"
#   applies_when: "When user asks to get data from an integration"
#   utility_score: 0.85
#
class TaskExperience < ApplicationRecord
  belongs_to :entity, optional: true  # nil = platform-wide experience
  belongs_to :evolution_cycle, optional: true

  # Task types map to GuidanceLibrary task types
  TASK_TYPES = %w[
    landing_page_create landing_page_edit website_create workflow_design
    crm_operation email_creation integration_setup app_design
    document_analysis analytics_review custom_domain_management general
  ].freeze

  SOURCE_TYPES = %w[
    semantic_advantage reflection manual evolution_cycle imported
    immediate_failure promoted_from_entity confidence_calibration
  ].freeze

  validates :task_type, presence: true, inclusion: { in: TASK_TYPES }
  validates :content, presence: true, length: { minimum: 20, maximum: 1000 }
  validates :source_type, inclusion: { in: SOURCE_TYPES }, allow_nil: true
  validates :utility_score, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }

  scope :for_entity, ->(entity) { where(entity: entity) }
  scope :for_task_type, ->(task_type) { where(task_type: task_type) }
  scope :active, -> { where(active: true) }
  scope :high_utility, -> { where('utility_score >= ?', 0.6) }
  scope :effective, -> { where('apply_count > 0').where('positive_outcome_count::float / NULLIF(apply_count, 0) >= 0.5') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_utility, -> { order(utility_score: :desc) }
  scope :platform_wide, -> { where(entity_id: nil) }

  # ═══════════════════════════════════════════════════════════════════════════
  # APPLICATION TRACKING
  # ═══════════════════════════════════════════════════════════════════════════

  # Record when this experience was injected into a prompt
  def record_application!
    increment!(:apply_count)
    update!(last_applied_at: Time.current)
  end

  # Record outcome after application
  def record_outcome!(success:)
    if success
      increment!(:positive_outcome_count)
      adjust_utility_score!(0.05)  # Small boost for success
      # Track last success for temporal decay
      update!(metadata: metadata.merge('last_positive_outcome_at' => Time.current.iso8601))
    else
      adjust_utility_score!(-0.02)  # Smaller penalty for failure (might not be experience's fault)
    end
  end

  # Calculate current success rate
  def success_rate
    return 0.5 if apply_count.zero?
    positive_outcome_count.to_f / apply_count
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # UTILITY MANAGEMENT
  # ═══════════════════════════════════════════════════════════════════════════

  def adjust_utility_score!(delta)
    new_score = (utility_score + delta).clamp(0.0, 1.0)
    update!(utility_score: new_score)
  end

  # Apply temporal decay to utility score
  # Experiences that haven't been validated recently should decay
  def apply_temporal_decay!
    return if apply_count < 5  # Not enough data to decay

    # Calculate days since last positive outcome
    last_success = metadata&.dig('last_positive_outcome_at')
    last_success_time = last_success ? Time.parse(last_success) : created_at
    days_since_success = ((Time.current - last_success_time) / 1.day).to_i

    # Only decay if no success in 30+ days
    return if days_since_success < 30

    # Exponential decay: 0.99^(days-30), minimum 0.5
    decay_factor = [0.99 ** (days_since_success - 30), 0.5].max
    decayed_score = utility_score * decay_factor

    if decayed_score < utility_score
      Rails.logger.info "[TaskExperience] Applying decay to #{id}: #{utility_score.round(3)} -> #{decayed_score.round(3)}"
      update!(
        utility_score: decayed_score,
        metadata: metadata.merge('last_decay_at' => Time.current.iso8601)
      )
    end
  end

  # Check if this experience is eligible for platform-wide promotion
  def promotable_to_platform?
    return false if entity_id.nil?  # Already platform-wide
    return false if utility_score < 0.85
    return false if apply_count < 15
    return false if success_rate < 0.75

    true
  end

  def deactivate!(reason: nil)
    update!(
      active: false,
      metadata: metadata.merge('deactivation_reason' => reason, 'deactivated_at' => Time.current.iso8601)
    )
    Rails.logger.info "[TaskExperience] Deactivated experience #{id}: #{content.truncate(50)} - #{reason}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CLASS METHODS
  # ═══════════════════════════════════════════════════════════════════════════

  class << self
    # Get experiences to inject for a task type
    # Returns top experiences by utility score for the given entity and task type
    def for_prompt(entity:, task_type:, limit: 5)
      # Get entity-specific experiences first
      entity_experiences = where(entity: entity, task_type: task_type)
                            .active
                            .high_utility
                            .by_utility
                            .limit(limit)

      # Fill with platform-wide experiences if needed
      platform_experiences = if entity_experiences.count < limit
                              platform_wide
                                .for_task_type(task_type)
                                .active
                                .high_utility
                                .by_utility
                                .limit(limit - entity_experiences.count)
                            else
                              []
                            end

      all_experiences = entity_experiences.to_a + platform_experiences.to_a
      return nil if all_experiences.empty?

      # Format for prompt injection
      formatted = all_experiences.map.with_index do |exp, i|
        prefix = exp.applies_when.present? ? "#{exp.applies_when}: " : ""
        "[#{i + 1}] #{prefix}#{exp.content}"
      end.join("\n")

      <<~EXPERIENCES
        ## 🧠 LEARNED EXPERIENCES (apply when relevant)
        
        #{formatted}
      EXPERIENCES
    end

    # Create a new experience from semantic advantage extraction
    def learn!(entity:, task_type:, content:, applies_when: nil, source_type: 'semantic_advantage', 
               evolution_cycle: nil, source_context: {})
      create!(
        entity: entity,
        task_type: task_type,
        content: content.strip,
        applies_when: applies_when,
        source_type: source_type,
        evolution_cycle: evolution_cycle,
        source_context: source_context,
        utility_score: 0.5,  # Start neutral, prove value through application
        generation: current_generation(entity)
      )
    end

    # Get current learning generation for an entity
    def current_generation(entity)
      where(entity: entity).maximum(:generation) || 1
    end

    # Increment generation (called at start of new learning cycle)
    def start_new_generation!(entity)
      current = current_generation(entity)
      current + 1
    end

    # Prune low-utility experiences to keep library focused
    def prune_low_utility!(entity:, keep_count: 50)
      experiences = where(entity: entity).active.by_utility.to_a
      
      return 0 if experiences.count <= keep_count
      
      # Keep the top experiences, prune the rest
      to_keep = experiences.first(keep_count)
      to_prune = experiences - to_keep
      
      pruned_count = 0
      to_prune.each do |exp| 
        exp.deactivate!(reason: 'low_utility_pruning')
        pruned_count += 1
      end
      
      pruned_count
    end

    # Merge similar experiences (called during evolution to consolidate)
    def merge_similar!(entity:, task_type:)
      # This could use embeddings for similarity, but for now just dedupe exact matches
      experiences = where(entity: entity, task_type: task_type).active
      
      # Group by content similarity (simple: exact match after normalization)
      grouped = experiences.group_by { |e| e.content.downcase.gsub(/\s+/, ' ').strip }
      
      merged_count = 0
      grouped.each do |_normalized, group|
        next if group.size <= 1
        
        # Keep the one with highest utility, deactivate others
        best = group.max_by(&:utility_score)
        group.reject { |e| e.id == best.id }.each do |exp|
          exp.deactivate!(reason: "merged_into_#{best.id}")
          merged_count += 1
        end
      end
      
      merged_count
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PLATFORM EXPERIENCE PROMOTION
    # Promote high-performing entity experiences to platform-wide
    # ═══════════════════════════════════════════════════════════════════════════

    def promote_to_platform!(experience)
      return false unless experience.promotable_to_platform?

      # Check if similar platform experience already exists
      existing = platform_wide
                   .for_task_type(experience.task_type)
                   .active
                   .find { |e| similar_content?(e.content, experience.content) }

      if existing
        # Update existing if new one has higher utility
        if experience.utility_score > existing.utility_score
          existing.update!(
            content: experience.content,
            utility_score: experience.utility_score,
            metadata: existing.metadata.merge(
              'promoted_from_entity_id' => experience.entity_id,
              'promoted_from_experience_id' => experience.id,
              'promoted_at' => Time.current.iso8601
            )
          )
          Rails.logger.info "[TaskExperience] Updated platform experience #{existing.id} from #{experience.id}"
        end
        return existing
      end

      # Create new platform-wide experience
      promoted = learn!(
        entity: nil,  # Platform-wide
        task_type: experience.task_type,
        content: experience.content,
        applies_when: experience.applies_when,
        source_type: 'promoted_from_entity',
        source_context: {
          original_entity_id: experience.entity_id,
          original_experience_id: experience.id,
          promoted_at: Time.current.iso8601,
          original_stats: {
            utility_score: experience.utility_score,
            apply_count: experience.apply_count,
            success_rate: experience.success_rate
          }
        }
      )

      # Start with the proven utility score
      promoted.update!(utility_score: experience.utility_score * 0.9)  # Slight discount for new context

      Rails.logger.info "[TaskExperience] Promoted experience #{experience.id} to platform-wide #{promoted.id}"
      promoted
    end

    # Check content similarity (simple version - could use embeddings)
    def similar_content?(content1, content2)
      normalized1 = content1.downcase.gsub(/\s+/, ' ').strip
      normalized2 = content2.downcase.gsub(/\s+/, ' ').strip

      # Jaccard similarity on words
      words1 = Set.new(normalized1.split)
      words2 = Set.new(normalized2.split)

      intersection = words1 & words2
      union = words1 | words2

      return false if union.empty?

      similarity = intersection.size.to_f / union.size
      similarity > 0.7
    end

    # Run promotion check for all eligible experiences
    def run_platform_promotion!
      promoted_count = 0

      # Find all eligible experiences across entities
      candidates = where.not(entity_id: nil)
                     .active
                     .where('utility_score >= ?', 0.85)
                     .where('apply_count >= ?', 15)

      candidates.find_each do |experience|
        next unless experience.promotable_to_platform?

        result = promote_to_platform!(experience)
        promoted_count += 1 if result
      end

      Rails.logger.info "[TaskExperience] Platform promotion complete: #{promoted_count} promoted"
      promoted_count
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # TEMPORAL DECAY (batch)
    # Apply decay to all stale experiences
    # ═══════════════════════════════════════════════════════════════════════════

    def apply_temporal_decay_all!
      decayed_count = 0

      active.where('apply_count >= ?', 5).find_each do |experience|
        before_score = experience.utility_score
        experience.apply_temporal_decay!
        decayed_count += 1 if experience.utility_score < before_score
      end

      Rails.logger.info "[TaskExperience] Temporal decay complete: #{decayed_count} experiences decayed"
      decayed_count
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONFLICT DETECTION
    # Find experiences that may contradict each other
    # ═══════════════════════════════════════════════════════════════════════════

    def detect_conflicts(entity:, task_type:)
      experiences = where(entity: entity, task_type: task_type).active.to_a
      return [] if experiences.count < 2

      conflicts = []

      experiences.each_with_index do |exp1, i|
        experiences[(i + 1)..].each do |exp2|
          # Check for potential conflicts:
          # 1. Similar content but different success rates
          # 2. Contains opposing keywords

          if potential_conflict?(exp1, exp2)
            conflicts << {
              experience_1: { id: exp1.id, content: exp1.content, success_rate: exp1.success_rate },
              experience_2: { id: exp2.id, content: exp2.content, success_rate: exp2.success_rate },
              conflict_type: determine_conflict_type(exp1, exp2)
            }
          end
        end
      end

      conflicts
    end

    def potential_conflict?(exp1, exp2)
      # Check for opposing success rates with similar topics
      return false if exp1.apply_count < 5 || exp2.apply_count < 5

      # Both should have enough data
      rate1 = exp1.success_rate
      rate2 = exp2.success_rate

      # One succeeds, one fails
      return true if rate1 > 0.7 && rate2 < 0.4
      return true if rate2 > 0.7 && rate1 < 0.4

      # Check for contradicting keywords
      content1 = exp1.content.downcase
      content2 = exp2.content.downcase

      opposing_pairs = [
        %w[always never],
        %w[before after],
        %w[skip verify],
        %w[quick thorough],
        %w[simple detailed]
      ]

      opposing_pairs.any? do |word1, word2|
        (content1.include?(word1) && content2.include?(word2)) ||
          (content1.include?(word2) && content2.include?(word1))
      end
    end

    def determine_conflict_type(exp1, exp2)
      rate1 = exp1.success_rate
      rate2 = exp2.success_rate

      if (rate1 > 0.7 && rate2 < 0.4) || (rate2 > 0.7 && rate1 < 0.4)
        'success_rate_divergence'
      else
        'semantic_opposition'
      end
    end

    # Resolve conflicts by keeping the higher-performing experience
    def resolve_conflicts!(entity:, task_type:)
      conflicts = detect_conflicts(entity: entity, task_type: task_type)
      return 0 if conflicts.empty?

      resolved_count = 0

      conflicts.each do |conflict|
        exp1 = find_by(id: conflict[:experience_1][:id])
        exp2 = find_by(id: conflict[:experience_2][:id])
        next unless exp1 && exp2

        # Keep the one with higher success rate and more data
        score1 = exp1.success_rate * Math.log(exp1.apply_count + 1)
        score2 = exp2.success_rate * Math.log(exp2.apply_count + 1)

        loser = score1 > score2 ? exp2 : exp1
        winner = score1 > score2 ? exp1 : exp2

        loser.deactivate!(reason: "conflict_resolution_favored_#{winner.id}")
        resolved_count += 1

        Rails.logger.info "[TaskExperience] Resolved conflict: kept #{winner.id}, deactivated #{loser.id}"
      end

      resolved_count
    end
  end
end
