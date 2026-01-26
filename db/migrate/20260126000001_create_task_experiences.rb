# frozen_string_literal: true

# TaskExperiences - Learned behaviors from comparing successful vs failed task executions
#
# This is the core of our Training-Free GRPO implementation:
# - Experiences are extracted by comparing groups of similar tasks
# - "Semantic advantage" = natural language description of what worked vs what didn't
# - Experiences are injected into prompts to improve future performance
#
# Integration with existing systems:
# - Populated by SemanticAdvantageService during EvolutionCycleService runs
# - Stored experiences complement GlobalKnowledgeArchive (which preserves agent retirement knowledge)
# - Injected via GuidanceLibrary.for_task() into DynamicContextService
# - Uses DecisionTrace data for source comparisons
#
class CreateTaskExperiences < ActiveRecord::Migration[7.2]
  def change
    create_table :task_experiences do |t|
      # entity_id can be null for platform-wide experiences
      t.references :entity, null: true, foreign_key: true

      # What type of task this experience applies to
      # Maps directly to GuidanceLibrary task types (e.g., :landing_page_edit, :integration_setup)
      t.string :task_type, null: false

      # The learned experience in natural language
      # e.g., "When editing landing page sections, always read current structure first 
      #        to avoid overwriting unintended sections"
      t.text :content, null: false

      # When this experience should be applied (for prompt injection relevance)
      # e.g., "When user asks to change a section", "Before calling an integration API"
      t.string :applies_when

      # Source tracking
      t.string :source_type  # 'semantic_advantage', 'reflection', 'manual', 'evolution_cycle'
      t.references :evolution_cycle, foreign_key: true, null: true  # Which cycle created this
      
      # Effectiveness tracking (Training-Free GRPO style)
      t.float :utility_score, default: 0.5      # How useful is this experience (0-1)
      t.integer :apply_count, default: 0        # How many times injected into prompts
      t.integer :positive_outcome_count, default: 0  # Times task succeeded when this was applied
      t.datetime :last_applied_at

      # Lifecycle
      t.boolean :active, default: true          # Can be deactivated if not helping
      t.integer :generation, default: 1         # Which learning generation created this
      
      # Context for when this was learned
      t.jsonb :source_context, default: {}      # Decision trace IDs, task examples, etc.
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Indexes for efficient querying
    add_index :task_experiences, [:entity_id, :task_type]
    add_index :task_experiences, [:entity_id, :task_type, :active]
    add_index :task_experiences, :utility_score
    add_index :task_experiences, [:entity_id, :active, :utility_score]
    
    # For global experiences that apply across entities (platform-level learnings)
    add_index :task_experiences, :task_type, where: "entity_id IS NULL"
  end
end
