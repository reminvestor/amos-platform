class ContactGroup < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  # Many-to-many association with contacts
  has_and_belongs_to_many :contacts,
                          -> { distinct },
                          class_name: "Contact",
                          after_add: :remove_from_other_groups

  # Email sequence associations
  has_many :email_sequences, dependent: :destroy

  # Validations
  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :user_id, presence: true

  # Callback to prevent deletion if contacts are associated
  before_destroy :check_for_contacts

  # Add a debugging method to check contact association
  def debug_contacts
    begin
      contacts_count = contacts.count
      Rails.logger.info("CONTACT_GROUP DEBUG [#{id}]: Has #{contacts_count} contacts")

      # Try to access the first few contacts to check for issues
      if contacts_count > 0
        sample = contacts.limit(5).to_a
        Rails.logger.info("CONTACT_GROUP DEBUG [#{id}]: First contact sample: #{sample.first.inspect}")
      end

      true
    rescue => e
      Rails.logger.error("CONTACT_GROUP DEBUG ERROR [#{id}]: #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      false
    end
  end

  private

  def check_for_contacts
    Rails.logger.info("CHECK_FOR_CONTACTS [#{id}]: Checking if contacts exist before destroy")
    begin
      if contacts.any?
        Rails.logger.info("CHECK_FOR_CONTACTS [#{id}]: Has contacts, preventing deletion")
        errors.add(:base, "Cannot delete group because it contains contacts")
        throw :abort
      end
    rescue => e
      Rails.logger.error("CHECK_FOR_CONTACTS ERROR [#{id}]: #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      errors.add(:base, "Error checking contacts: #{e.message}")
      throw :abort
    end
  end

  def remove_from_other_groups(contact)
    # Skip if contact is nil or already being processed
    return unless contact

    begin
      Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Contact [#{contact.id}] added to group [#{id}], checking other groups")

      # Only remove from groups in the same entity
      if entity_id.present?
        Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Group has entity_id [#{entity_id}], finding other groups in same entity")
        # Find groups in the same entity, excluding this one
        same_entity_groups = ContactGroup.where(entity_id: entity_id).where.not(id: id)
        Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Found #{same_entity_groups.count} other groups in same entity")

        # Remove contact from all groups in the same entity
        same_entity_groups.each do |group|
          # Use delete instead of delete_all to trigger callbacks
          if group.contacts.include?(contact)
            Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Removing contact [#{contact.id}] from group [#{group.id}]")
            # Use a direct SQL query to avoid callbacks and race conditions
            deleted = ContactGroupsContact.where(contact_id: contact.id, contact_group_id: group.id).delete_all
            Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Deleted #{deleted} join records")
          end
        end
      else
        Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Group has no entity_id, finding other global groups")
        # For global groups (no entity), only remove from other global groups
        global_groups = ContactGroup.where(entity_id: nil).where.not(id: id)
        Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Found #{global_groups.count} other global groups")

        # Remove contact from all global groups
        global_groups.each do |group|
          if group.contacts.include?(contact)
            Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Removing contact [#{contact.id}] from global group [#{group.id}]")
            # Use a direct SQL query to avoid callbacks and race conditions
            deleted = ContactGroupsContact.where(contact_id: contact.id, contact_group_id: group.id).delete_all
            Rails.logger.info("REMOVE_FROM_OTHER_GROUPS: Deleted #{deleted} join records")
          end
        end
      end
    rescue => e
      # Log error but don't fail the operation
      Rails.logger.error("REMOVE_FROM_OTHER_GROUPS ERROR: #{e.class.name}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
    end
  end
end
