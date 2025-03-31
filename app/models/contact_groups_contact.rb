# Model representing the join table between contacts and contact groups
class ContactGroupsContact < ApplicationRecord
  belongs_to :contact
  belongs_to :contact_group
  
  # Validations
  validates :contact_id, uniqueness: { scope: :contact_group_id }
end 