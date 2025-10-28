class NormalizeOperationIds < ActiveRecord::Migration[8.0]
  def up
    # Normalize all operation_id values to format: slug.operation_name
    # Remove version suffixes like .v3, .v2020-08-27, etc.
    
    IntegrationOperation.find_each do |operation|
      next unless operation.integration
      
      # Extract the base operation name without version suffix
      # Handles: stripe.list_customers.v2020-08-27 → stripe.list_customers
      #          quickbooks.get_company_info.v3 → quickbooks.get_company_info
      base_operation_id = operation.operation_id.sub(/\.v[\d-]+$/, '')
      
      if base_operation_id != operation.operation_id
        puts "Normalizing: #{operation.operation_id} → #{base_operation_id}"
        operation.update_column(:operation_id, base_operation_id)
      end
    end
    
    puts "✅ Operation IDs normalized to slug.operation_name format"
  end
  
  def down
    # This migration is not reversible since we lose version information
    raise ActiveRecord::IrreversibleMigration, "Cannot restore version suffixes without original data"
  end
end
