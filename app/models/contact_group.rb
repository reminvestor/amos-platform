class ContactGroup < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  
  # Many-to-many association with contacts
  has_and_belongs_to_many :contacts, 
                          -> { distinct }, 
                          class_name: 'Contact',
                          after_add: :remove_from_other_groups
  
  # Validations
  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :user_id, presence: true
  
  # Callback to prevent deletion if contacts are associated
  before_destroy :check_for_contacts
  
  private
  
  def check_for_contacts
    if contacts.any?
      errors.add(:base, "Cannot delete group because it contains contacts")
      throw :abort
    end
  end
  
  def remove_from_other_groups(contact)
    # Skip if contact is nil or already being processed
    return unless contact
    
    begin
      # Only remove from groups in the same entity
      if entity_id.present?
        # Find groups in the same entity, excluding this one
        same_entity_groups = ContactGroup.where(entity_id: entity_id).where.not(id: id)
        
        # Remove contact from all groups in the same entity
        same_entity_groups.each do |group|
          # Use delete instead of delete_all to trigger callbacks
          if group.contacts.include?(contact)
            # Use a direct SQL query to avoid callbacks and race conditions
            ContactGroupsContact.where(contact_id: contact.id, contact_group_id: group.id).delete_all
          end
        end
      else
        # For global groups (no entity), only remove from other global groups
        global_groups = ContactGroup.where(entity_id: nil).where.not(id: id)
        
        # Remove contact from all global groups
        global_groups.each do |group|
          if group.contacts.include?(contact)
            # Use a direct SQL query to avoid callbacks and race conditions
            ContactGroupsContact.where(contact_id: contact.id, contact_group_id: group.id).delete_all
          end
        end
      end
    rescue => e
      # Log error but don't fail the operation
      Rails.logger.error("Error in remove_from_other_groups: #{e.message}\n#{e.backtrace.join("\n")}")
    end
  end
end
