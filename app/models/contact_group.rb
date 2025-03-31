class ContactGroup < ApplicationRecord
  belongs_to :user
  belongs_to :entity, optional: true
  
  # Many-to-many association with contacts
  has_and_belongs_to_many :contacts, -> { distinct }, class_name: 'Contact'
  
  # Validations
  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :user_id, presence: true
  
  # Callback to prevent deletion if contacts are associated
  before_destroy :check_for_contacts
  
  # Callbacks
  after_add_for_contacts :remove_from_other_groups
  
  private
  
  def check_for_contacts
    if contacts.any?
      errors.add(:base, "Cannot delete group because it contains contacts")
      throw :abort
    end
  end
  
  def remove_from_other_groups(contact)
    # Remove contact from other groups
    ContactGroup.where.not(id: id).each do |group|
      group.contacts.delete(contact)
    end
  end
end
