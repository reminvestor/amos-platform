# frozen_string_literal: true

class CreateSystemSkillsAndRevisions < ActiveRecord::Migration[8.0]
  def change
    create_table :system_skills do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :skill_type, null: false, default: 'integration'
      t.text :content, null: false
      t.string :source, null: false, default: 'built-in'
      t.string :status, null: false, default: 'active'

      # Matching metadata
      t.string :integration_name
      t.string :keywords, array: true, default: []

      # Performance tracking
      t.integer :injection_count, default: 0
      t.integer :positive_outcomes, default: 0
      t.integer :negative_outcomes, default: 0
      t.float :effectiveness_score

      # Versioning
      t.integer :version, default: 1
      t.datetime :last_evolved_at
      t.string :last_evolved_by

      # Entity scoping (nil = global/system skill)
      t.references :entity, foreign_key: true, null: true

      t.timestamps
    end

    add_index :system_skills, :slug, unique: true
    add_index :system_skills, :skill_type
    add_index :system_skills, :integration_name
    add_index :system_skills, :status

    create_table :skill_revisions do |t|
      t.references :system_skill, null: false, foreign_key: true
      t.integer :version, null: false
      t.text :content, null: false
      t.text :previous_content
      t.string :change_source, null: false
      t.text :change_reason
      t.jsonb :change_details, default: {}

      # Who/what made this change
      t.string :author_type
      t.bigint :author_id

      # Review status
      t.string :status, null: false, default: 'applied'
      t.datetime :reviewed_at
      t.references :reviewed_by, foreign_key: { to_table: :users }, null: true

      t.timestamps
    end

    add_index :skill_revisions, [:system_skill_id, :version], unique: true
    add_index :skill_revisions, :change_source
    add_index :skill_revisions, :status

    # Track which skills were injected into conversations
    create_table :skill_injection_logs do |t|
      t.references :system_skill, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :session_id
      t.string :injection_reason
      t.boolean :outcome_positive

      # Link to what happened after injection
      t.integer :tool_calls_count, default: 0
      t.integer :tool_calls_succeeded, default: 0
      t.integer :tool_calls_failed, default: 0

      t.timestamps
    end

    add_index :skill_injection_logs, :session_id
    add_index :skill_injection_logs, [:system_skill_id, :outcome_positive]
    add_index :skill_injection_logs, :created_at
  end
end
