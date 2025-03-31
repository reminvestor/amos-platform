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
    # Only remove from groups in the same entity
    if entity_id.present?
      # Find groups in the same entity, excluding this one
      same_entity_groups = ContactGroup.where(entity_id: entity_id).where.not(id: id)
      
      # Remove contact from all groups in the same entity
      same_entity_groups.each do |group|
        group.contacts.delete(contact) if group.contacts.include?(contact)
      end
    else
      # For global groups (no entity), only remove from other global groups
      global_groups = ContactGroup.where(entity_id: nil).where.not(id: id)
      
      # Remove contact from all global groups
      global_groups.each do |group|
        group.contacts.delete(contact) if group.contacts.include?(contact)
      end
    end
  end
end
