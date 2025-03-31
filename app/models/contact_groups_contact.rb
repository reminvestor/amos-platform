# Model representing the join table between contacts and contact groups
class ContactGroupsContact < ApplicationRecord
  # Debug schema information
  def self.debug_schema
    begin
      columns_info = connection.schema_cache.columns(table_name)
      column_names = columns_info.map(&:name)
      Rails.logger.info("CONTACT_GROUPS_CONTACT DEBUG: Available columns: #{column_names.join(', ')}")
      return column_names
    rescue => e
      Rails.logger.error("CONTACT_GROUPS_CONTACT DEBUG ERROR: Failed to get schema - #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      return []
    end
  end
  
  # Call schema debug on load
  debug_schema
  
  belongs_to :contact
  belongs_to :contact_group
  
  # Validations
  validates :contact_id, uniqueness: { scope: :contact_group_id }
end 