class EntityUser < ApplicationRecord
  # Relationships
  belongs_to :entity
  belongs_to :user
  
  # Validations
  validates :user_id, uniqueness: { scope: :entity_id, message: "already belongs to this entity" }
  validates :role, presence: true, inclusion: { in: %w[owner admin member] }
  
  # Ensure at least one owner per entity
  after_update :ensure_entity_has_owner, if: -> { saved_change_to_role? && role_before_last_save == 'owner' }
  before_destroy :prevent_owner_removal, if: -> { role == 'owner' }
  
  # Check if user has specific role
  def owner?
    role == 'owner'
  end
  
  def admin?
    role == 'admin' || role == 'owner'
  end
  
  def member?
    role == 'member'
  end
  
  private
  
  def ensure_entity_has_owner
    if entity.entity_users.where(role: 'owner').count.zero?
      # Revert the change if there would be no owner
      update_column(:role, 'owner')
      errors.add(:base, "Entity must have at least one owner")
      throw(:abort)
    end
  end
  
  def prevent_owner_removal
    if entity.entity_users.where(role: 'owner').count <= 1
      errors.add(:base, "Cannot remove the only owner of an entity")
      throw(:abort)
    end
  end
end
