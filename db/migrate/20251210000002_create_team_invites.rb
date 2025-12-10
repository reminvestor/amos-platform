# frozen_string_literal: true

class CreateTeamInvites < ActiveRecord::Migration[8.0]
  def change
    create_table :team_invites do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      
      t.string :email, null: false
      t.string :role, default: 'member', null: false
      t.string :token, null: false
      t.string :status, default: 'pending', null: false
      
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.datetime :declined_at
      
      t.timestamps
    end
    
    add_index :team_invites, :token, unique: true
    add_index :team_invites, [:entity_id, :email], unique: true, where: "status = 'pending'"
  end
end
