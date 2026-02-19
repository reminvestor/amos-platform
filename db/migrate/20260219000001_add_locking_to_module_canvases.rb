# frozen_string_literal: true

class AddLockingToModuleCanvases < ActiveRecord::Migration[8.0]
  def change
    add_column :module_canvases, :is_locked, :boolean, default: false, null: false
    add_column :module_canvases, :locked_at, :datetime
    add_column :module_canvases, :locked_by_id, :bigint
    add_column :module_canvases, :lock_reason, :string

    add_index :module_canvases, :is_locked
    add_index :module_canvases, :locked_by_id
  end
end
