# frozen_string_literal: true

class AddUserToConnections < ActiveRecord::Migration[8.0]
  def change
    # Add user_id to connections - connections are user-scoped (e.g., each user has their own Gmail)
    add_reference :connections, :user, foreign_key: true, null: true
    
    # Add index for efficient lookups by user + integration
    add_index :connections, [:user_id, :integration_id], name: 'index_connections_on_user_and_integration'
  end
end

