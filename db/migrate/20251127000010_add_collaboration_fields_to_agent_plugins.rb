class AddCollaborationFieldsToAgentPlugins < ActiveRecord::Migration[8.0]
  def change
    # Status fields
    add_column :agent_plugins, :probation_started_at, :datetime
    add_column :agent_plugins, :probation_reasons, :jsonb, default: []
    add_column :agent_plugins, :priority_score, :float, default: 1.0
    add_column :agent_plugins, :sabbatical_until, :datetime

    # Evolution tracking
    add_reference :agent_plugins, :parent_agent, foreign_key: { to_table: :agent_plugins }
    add_column :agent_plugins, :generation, :integer, default: 1
    add_column :agent_plugins, :lineage, :jsonb, default: []
    add_column :agent_plugins, :graduated_at, :datetime

    # Specialization
    add_column :agent_plugins, :primary_niche, :string
    add_column :agent_plugins, :specialties, :jsonb, default: []
    add_column :agent_plugins, :weaknesses, :jsonb, default: []
    add_column :agent_plugins, :protected_status, :boolean, default: false

    # Refinement tracking
    add_column :agent_plugins, :last_refinement_at, :datetime
    add_column :agent_plugins, :refinement_priority, :float, default: 0.0

    # School tracking
    add_reference :agent_plugins, :school_enrollment, foreign_key: { to_table: :agent_school_enrollments }

    # Indexes
    add_index :agent_plugins, :priority_score
    add_index :agent_plugins, :generation
    add_index :agent_plugins, :primary_niche
    add_index :agent_plugins, :protected_status
  end
end

