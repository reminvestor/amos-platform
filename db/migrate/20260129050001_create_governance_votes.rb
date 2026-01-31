# frozen_string_literal: true

class CreateGovernanceVotes < ActiveRecord::Migration[7.0]
  def change
    create_table :governance_votes do |t|
      t.references :governance_proposal, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.string :vote, null: false  # for, against, abstain
      t.decimal :voting_power, precision: 20, scale: 4, null: false
      t.datetime :voted_at, null: false

      t.timestamps
    end

    add_index :governance_votes, [:governance_proposal_id, :user_id], unique: true, name: 'idx_gov_votes_proposal_user'
    add_index :governance_votes, :vote
  end
end
