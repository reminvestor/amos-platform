# frozen_string_literal: true

class CreateGovernanceProposals < ActiveRecord::Migration[7.0]
  def change
    create_table :governance_proposals do |t|
      t.references :proposer, null: false, foreign_key: { to_table: :users }
      t.references :entity, foreign_key: true

      t.string :title, null: false
      t.text :description, null: false
      t.string :proposal_type, null: false  # r_and_d, treasury, feature, partnership, parameter, constitutional
      t.string :status, null: false, default: 'discussion'

      t.decimal :staked_amount, precision: 20, scale: 4, default: 0
      
      t.datetime :voting_started_at
      t.datetime :finalized_at
      t.datetime :executed_at

      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :governance_proposals, :proposal_type
    add_index :governance_proposals, :status
    add_index :governance_proposals, :voting_started_at
  end
end
