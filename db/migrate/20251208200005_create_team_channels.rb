class CreateTeamChannels < ActiveRecord::Migration[7.1]
  def change
    create_table :team_channels do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :channel_type, default: 'general'  # general, project, integration
      t.jsonb :settings, default: {}
      t.boolean :is_default, default: false
      t.boolean :archived, default: false

      t.timestamps
    end

    add_index :team_channels, [:entity_id, :name], unique: true
    add_index :team_channels, :channel_type
    add_index :team_channels, :archived
  end
end
