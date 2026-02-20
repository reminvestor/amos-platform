# frozen_string_literal: true

module Learning
  # SemanticAdvantageService - The core of Training-Free GRPO
  #
  # This service implements the key insight from the Training-Free GRPO paper:
  # Instead of calculating numerical advantages for gradient updates,
  # we extract "semantic advantages" - natural language descriptions of
  # what made successful interactions work and what caused failures.
  #
  # The process:
  # 1. Group similar task executions (rollouts)
  # 2. Separate winners (success + high quality) from losers (failures)
  # 3. Use LLM to introspect and extract generalizable lessons
  # 4. Store as TaskExperience for future prompt injection
  #
  # Integration with existing systems:
  # - Uses DecisionTrace for execution data (Context Graph)
  # - Called by EvolutionCycleService during evolution phases
  # - Stores results in TaskExperience (our experience library)
  # - Experiences injected via GuidanceLibrary
  #
  # References Training-Free GRPO paper concepts:
  # - Group rollouts (G = 3-5 outputs per query type)
  # - Semantic advantage (natural language, not numerical)
  # - Experience library ℰ with add/modify/delete operations
  #
  class SemanticAdvantageService
    attr_reader :entity

    # Configuration aligned with paper recommendations
    MIN_GROUP_SIZE = 3          # Minimum rollouts needed for comparison
    MAX_GROUP_SIZE = 20         # Cap for performance
    MIN_WINNERS = 1             # Need at least one success
    MIN_LOSERS = 1              # Need at least one failure
    MAX_EXPERIENCES_PER_RUN = 5 # Don't overwhelm the experience library

    def initialize(entity:)
      @entity = entity
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN ENTRY POINT
    # Called by EvolutionCycleService during the ANALYZE phase
    # ═══════════════════════════════════════════════════════════════════════════

    def extract_experiences(window: 7.days, task_types: nil)
      Rails.logger.info "[SemanticAdvantage] Starting experience extraction for entity #{entity.id}"

      results = {
        task_types_analyzed: [],
        experiences_created: 0,
        experiences_modified: 0,
        experiences_deleted: 0,
        errors: []
      }

      # Get task types to analyze
      types_to_analyze = task_types || active_task_types(window)

      types_to_analyze.each do |task_type|
        begin
          type_result = extract_for_task_type(task_type, window: window)
          
          results[:task_types_analyzed] << task_type
          results[:experiences_created] += type_result[:created]
          results[:experiences_modified] += type_result[:modified]
          results[:experiences_deleted] += type_result[:deleted]
        rescue => e
          Rails.logger.error "[SemanticAdvantage] Error processing #{task_type}: #{e.message}"
          results[:errors] << { task_type: task_type, error: e.message }
        end
      end

      Rails.logger.info "[SemanticAdvantage] Extraction complete: #{results[:experiences_created]} created, " \
                        "#{results[:experiences_modified]} modified, #{results[:experiences_deleted]} deleted"

      results
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # TASK TYPE PROCESSING
    # ═══════════════════════════════════════════════════════════════════════════

    def extract_for_task_type(task_type, window: 7.days)
      Rails.logger.info "[SemanticAdvantage] Processing task type: #{task_type}"

      # Step 1: Get decision traces for this task type
      traces = get_decision_traces(task_type, window)
      return { created: 0, modified: 0, deleted: 0 } if traces.count < MIN_GROUP_SIZE

      # Step 2: Separate winners and losers
      winners, losers = separate_outcomes(traces)
      
      if winners.count < MIN_WINNERS || losers.count < MIN_LOSERS
        Rails.logger.info "[SemanticAdvantage] Skipping #{task_type}: insufficient variance " \
                          "(#{winners.count} winners, #{losers.count} losers)"
        return { created: 0, modified: 0, deleted: 0 }
      end

      # Step 3: Summarize trajectories (like paper's trajectory summarization step)
      winner_summaries = summarize_trajectories(winners.limit(MAX_GROUP_SIZE / 2))
      loser_summaries = summarize_trajectories(losers.limit(MAX_GROUP_SIZE / 2))

      # Step 4: Extract semantic advantage via LLM comparison
      advantages = extract_semantic_advantages(
        task_type: task_type,
        winner_summaries: winner_summaries,
        loser_summaries: loser_summaries
      )

      return { created: 0, modified: 0, deleted: 0 } if advantages.empty?

      # Step 5: Update experience library (add/modify/delete operations)
      update_experience_library(task_type, advantages)
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # DATA GATHERING
    # ═══════════════════════════════════════════════════════════════════════════

    def active_task_types(window)
      # Get task types that had activity in the window
      # Use DecisionTrace metadata to identify task types
      DecisionTrace.where(entity: entity)
                   .where('created_at > ?', window.ago)
                   .where.not(metadata: nil)
                   .pluck(Arel.sql("DISTINCT metadata->>'task_type'"))
                   .compact
                   .select { |t| TaskExperience::TASK_TYPES.include?(t) }
    end

    def get_decision_traces(task_type, window)
      DecisionTrace.where(entity: entity)
                   .where('created_at > ?', window.ago)
                   .where("metadata->>'task_type' = ?", task_type)
                   .where.not(outcome: nil)  # Only those with recorded outcomes
                   .order(created_at: :desc)
    end

    def separate_outcomes(traces)
      # Winners: successful with good quality
      winners = traces.where(outcome: 'success')
                      .where('outcome_quality_score >= 0.7 OR outcome_quality_score IS NULL')

      # Losers: failed or low quality
      losers = traces.where(outcome: 'failure')
                     .or(traces.where('outcome_quality_score < 0.5'))

      [winners, losers]
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # TRAJECTORY SUMMARIZATION
    # Paper: "For each output, ask LLM to provide a summary"
    # ═══════════════════════════════════════════════════════════════════════════

    def summarize_trajectories(traces)
      traces.map do |trace|
        {
          id: trace.id,
          decision_type: trace.decision_type,
          summary: trace.decision_summary,
          reasoning: trace.reasoning,
          context: trace.context_gathered,
          outcome: trace.outcome,
          quality: trace.outcome_quality_score,
          is_exception: trace.is_exception,
          tools_used: extract_tools_used(trace),
          model_used: trace.metadata&.dig('model_used')
        }
      end
    end

    def extract_tools_used(trace)
      # Extract tool calls from context or child decisions
      tools = []
      
      if trace.context_gathered.is_a?(Hash)
        tools << trace.context_gathered['tool_name'] if trace.context_gathered['tool_name']
      end
      
      trace.child_decisions.where(decision_type: 'action').each do |child|
        tools << child.metadata['tool_name'] if child.metadata['tool_name']
      end
      
      tools.uniq
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # SEMANTIC ADVANTAGE EXTRACTION
    # Paper: "Leverage LLMs to introspect on each group and distill a semantic advantage"
    # ═══════════════════════════════════════════════════════════════════════════

    def extract_semantic_advantages(task_type:, winner_summaries:, loser_summaries:)
      prompt = build_comparison_prompt(task_type, winner_summaries, loser_summaries)
      
      begin
        response = bedrock_service.quick_completion(prompt)
        parse_advantages_response(response)
      rescue => e
        Rails.logger.error "[SemanticAdvantage] LLM extraction failed: #{e.message}"
        []
      end
    end

    def build_comparison_prompt(task_type, winner_summaries, loser_summaries)
      existing_experiences = TaskExperience.where(entity: entity, task_type: task_type)
                                           .active
                                           .by_utility
                                           .limit(10)
                                           .pluck(:content)

      <<~PROMPT
        You are analyzing AI agent task executions to extract generalizable lessons.
        
        ## Task Type: #{task_type.to_s.titleize}
        
        ## Successful Executions (Winners)
        #{format_summaries(winner_summaries)}
        
        ## Failed Executions (Losers)
        #{format_summaries(loser_summaries)}
        
        ## Existing Experiences (already learned)
        #{existing_experiences.any? ? existing_experiences.map.with_index { |e, i| "[E#{i + 1}] #{e}" }.join("\n") : "(none yet)"}
        
        ## Your Task
        
        Analyze what made winners succeed and losers fail. Extract 1-3 NEW generalizable lessons.
        
        For each lesson:
        1. Focus on actionable, strategic patterns (not specific data values)
        2. Start with context: "When [situation], [do this] to [achieve outcome]"
        3. Be specific enough to be useful, general enough to apply broadly
        4. Don't repeat existing experiences - add NEW insights or MODIFY existing ones
        5. If you notice model-specific patterns (e.g., one model consistently succeeds/fails at this task type),
           include that as a lesson with source_type "model_routing"
        
        ## Response Format (JSON)
        
        Return a JSON array with operations:
        
        ```json
        [
          {
            "operation": "add",
            "content": "When executing integration APIs, always verify connection status first to avoid cryptic auth errors",
            "applies_when": "Before calling integration tools",
            "source_type": "semantic_advantage"
          },
          {
            "operation": "add",
            "content": "Claude Opus significantly outperforms Qwen on integration setup tasks requiring complex multi-step API orchestration",
            "applies_when": "When selecting model for integration tasks",
            "source_type": "model_routing"
          },
          {
            "operation": "modify",
            "experience_index": 2,
            "content": "Improved version of experience E2 with additional insight...",
            "reason": "Original was too vague, adding specificity from failure analysis"
          },
          {
            "operation": "delete",
            "experience_index": 1,
            "reason": "This advice actually led to failures - contradicted by evidence"
          }
        ]
        ```
        
        Operations:
        - "add": New experience to add (include content, applies_when)
        - "modify": Update existing experience (include experience_index, content, reason)
        - "delete": Remove unhelpful experience (include experience_index, reason)
        
        ONLY return the JSON array, no other text.
      PROMPT
    end

    def format_summaries(summaries)
      summaries.map.with_index do |s, i|
        tools = s[:tools_used].any? ? "Tools: #{s[:tools_used].join(', ')}" : "No tools"
        quality = s[:quality] ? "Quality: #{s[:quality]}" : ""
        exception = s[:is_exception] ? "[EXCEPTION]" : ""
        model = s[:model_used].present? ? "Model: #{s[:model_used]}" : ""
        
        <<~SUMMARY
          ### Execution #{i + 1} #{exception}
          - Summary: #{s[:summary]}
          - Reasoning: #{s[:reasoning].to_s.truncate(200)}
          - #{tools}
          - #{model}
          - Outcome: #{s[:outcome]} #{quality}
        SUMMARY
      end.join("\n")
    end

    def parse_advantages_response(response)
      # Extract JSON from response (might be wrapped in markdown code blocks)
      json_match = response.match(/\[[\s\S]*\]/)
      return [] unless json_match
      
      JSON.parse(json_match[0])
    rescue JSON::ParserError => e
      Rails.logger.warn "[SemanticAdvantage] Failed to parse response: #{e.message}"
      []
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # EXPERIENCE LIBRARY UPDATE
    # Paper: "Update experience library ℰ using all semantic advantages"
    # ═══════════════════════════════════════════════════════════════════════════

    def update_experience_library(task_type, advantages)
      existing = TaskExperience.where(entity: entity, task_type: task_type)
                               .active
                               .by_utility
                               .to_a

      created = 0
      modified = 0
      deleted = 0

      advantages.first(MAX_EXPERIENCES_PER_RUN).each do |advantage|
        case advantage['operation']
        when 'add'
          create_experience(task_type, advantage)
          created += 1

        when 'modify'
          idx = advantage['experience_index'].to_i - 1
          if idx >= 0 && idx < existing.count
            modify_experience(existing[idx], advantage)
            modified += 1
          end

        when 'delete'
          idx = advantage['experience_index'].to_i - 1
          if idx >= 0 && idx < existing.count
            delete_experience(existing[idx], advantage)
            deleted += 1
          end
        end
      end

      # Prune if library is getting too large
      TaskExperience.prune_low_utility!(entity: entity, keep_count: 50)

      { created: created, modified: modified, deleted: deleted }
    end

    def create_experience(task_type, advantage)
      TaskExperience.learn!(
        entity: entity,
        task_type: task_type,
        content: advantage['content'],
        applies_when: advantage['applies_when'],
        source_type: advantage['source_type'] || 'semantic_advantage',
        source_context: {
          extracted_at: Time.current.iso8601,
          generation: TaskExperience.current_generation(entity)
        }
      )
      
      Rails.logger.info "[SemanticAdvantage] Created experience: #{advantage['content'].truncate(60)}"
    end

    def modify_experience(experience, advantage)
      old_content = experience.content
      
      experience.update!(
        content: advantage['content'],
        metadata: experience.metadata.merge(
          'modified_at' => Time.current.iso8601,
          'modification_reason' => advantage['reason'],
          'previous_content' => old_content
        )
      )
      
      Rails.logger.info "[SemanticAdvantage] Modified experience #{experience.id}: #{advantage['reason']}"
    end

    def delete_experience(experience, advantage)
      experience.deactivate!(reason: advantage['reason'])
      Rails.logger.info "[SemanticAdvantage] Deleted experience #{experience.id}: #{advantage['reason']}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MODEL PERFORMANCE ANALYSIS
    # Extracts model-specific routing insights from DecisionTrace + ModelQualityLog
    # ═══════════════════════════════════════════════════════════════════════════

    public

    def extract_model_routing_insights(window: 7.days)
      return [] unless defined?(ModelQualityLog)

      Rails.logger.info "[SemanticAdvantage] Extracting model routing insights for entity #{entity.id}"

      insights = []

      # Analyze DecisionTrace outcomes grouped by model
      model_outcomes = DecisionTrace.where(entity: entity)
                                     .where('created_at > ?', window.ago)
                                     .where.not(outcome: nil)
                                     .where("metadata->>'model_used' IS NOT NULL")
                                     .group(Arel.sql("metadata->>'model_used'"), :outcome)
                                     .count

      # Build per-model stats
      model_stats = {}
      model_outcomes.each do |(model, outcome), count|
        model_stats[model] ||= { success: 0, failure: 0, total: 0 }
        model_stats[model][outcome.to_sym] = count
        model_stats[model][:total] += count
      end

      # Also group by task_type + model for task-specific routing
      task_model_outcomes = DecisionTrace.where(entity: entity)
                                          .where('created_at > ?', window.ago)
                                          .where.not(outcome: nil)
                                          .where("metadata->>'model_used' IS NOT NULL")
                                          .where("metadata->>'task_type' IS NOT NULL")
                                          .group(
                                            Arel.sql("metadata->>'task_type'"),
                                            Arel.sql("metadata->>'model_used'"),
                                            :outcome
                                          ).count

      # Build per-task-type model rankings
      task_model_stats = {}
      task_model_outcomes.each do |(task_type, model, outcome), count|
        task_model_stats[task_type] ||= {}
        task_model_stats[task_type][model] ||= { success: 0, failure: 0, total: 0 }
        task_model_stats[task_type][model][outcome.to_sym] = count
        task_model_stats[task_type][model][:total] += count
      end

      # Generate insights for task types where models differ significantly
      task_model_stats.each do |task_type, models|
        next if models.size < 2

        ranked = models.map do |model, stats|
          next if stats[:total] < 3
          rate = stats[:success].to_f / stats[:total]
          { model: model, success_rate: rate, total: stats[:total] }
        end.compact.sort_by { |m| -m[:success_rate] }

        next if ranked.size < 2

        best = ranked.first
        worst = ranked.last
        gap = best[:success_rate] - worst[:success_rate]

        if gap > 0.15 && best[:total] >= 5
          insights << {
            task_type: task_type,
            best_model: best[:model],
            best_rate: (best[:success_rate] * 100).round(1),
            worst_model: worst[:model],
            worst_rate: (worst[:success_rate] * 100).round(1),
            sample_size: ranked.sum { |r| r[:total] }
          }
        end
      end

      # Store significant insights as TaskExperience records
      insights.first(3).each do |insight|
        content = "For #{insight[:task_type].to_s.titleize} tasks, " \
                  "#{insight[:best_model]} achieves #{insight[:best_rate]}% success rate " \
                  "vs #{insight[:worst_model]} at #{insight[:worst_rate]}% " \
                  "(based on #{insight[:sample_size]} executions). " \
                  "Prefer #{insight[:best_model]} for this task type."

        existing = TaskExperience.where(entity: entity, source_type: 'model_routing')
                                 .where("content LIKE ?", "%#{insight[:task_type].to_s.titleize}%")
                                 .active
                                 .first

        if existing
          existing.update!(content: content, metadata: existing.metadata.merge(
            'updated_at' => Time.current.iso8601,
            'stats' => insight
          ))
        else
          TaskExperience.learn!(
            entity: entity,
            task_type: insight[:task_type],
            content: content,
            applies_when: "When selecting model for #{insight[:task_type]} tasks",
            source_type: 'model_routing',
            source_context: { stats: insight, extracted_at: Time.current.iso8601 }
          )
        end
      end

      Rails.logger.info "[SemanticAdvantage] Generated #{insights.size} model routing insights"
      insights
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def bedrock_service
      @bedrock_service ||= BedrockService.new(entity: entity)
    end
  end
end
