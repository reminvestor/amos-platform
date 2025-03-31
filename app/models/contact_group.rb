class ContactGroup < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  
  # Many-to-many association with contacts
  has_and_belongs_to_many :contacts
  
  # Validations
  validates :name, presence: true, uniqueness: { scope: :user_id }
  
  # Callback to prevent deletion if contacts are associated
  before_destroy :check_for_contacts
  
  # When adding a contact, remove it from other groups first
  before_add :remove_from_other_groups
  
  private
  
  def check_for_contacts
    if contacts.any?
      errors.add(:base, "Cannot delete group because it contains contacts")
      throw :abort
    end
  end
  
  def remove_from_other_groups
    contact = contacts.last
    ContactGroup.where(user: user).where.not(id: id).each do |group|
      group.contacts.delete(contact)
    end
  end
end
