# frozen_string_literal: true

class AddTransformCodeToSyncConfig < ActiveRecord::Migration[7.1]
  def change
    # Add columns to store AI-generated transform code (idempotent - check if exists)
    unless column_exists?(:integration_sync_configs, :transform_code)
      add_column :integration_sync_configs, :transform_code, :text
    end
    
    unless column_exists?(:integration_sync_configs, :transform_code_version)
      add_column :integration_sync_configs, :transform_code_version, :integer, default: 1
    end
    
    unless column_exists?(:integration_sync_configs, :transform_code_generated_at)
      add_column :integration_sync_configs, :transform_code_generated_at, :datetime
    end
    
    unless column_exists?(:integration_sync_configs, :transform_code_generated_by)
      add_column :integration_sync_configs, :transform_code_generated_by, :string
    end
    
    # Post-sync workflow integration (no FK constraint - workflows table may not exist)
    unless column_exists?(:integration_sync_configs, :post_sync_workflow_id)
      add_column :integration_sync_configs, :post_sync_workflow_id, :bigint
    end
    
    unless index_exists?(:integration_sync_configs, :post_sync_workflow_id)
      add_index :integration_sync_configs, :post_sync_workflow_id
    end
    
    # Store sample input/output for testing
    unless column_exists?(:integration_sync_configs, :sample_input)
      add_column :integration_sync_configs, :sample_input, :jsonb, default: {}
    end
    
    unless column_exists?(:integration_sync_configs, :sample_output)
      add_column :integration_sync_configs, :sample_output, :jsonb, default: {}
    end
  end
end

