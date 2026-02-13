# frozen_string_literal: true

# EntityShareable - Mixin for assets that can be shared with the entity
#
# Models including this concern must have:
#   - entity_id column (required)
#   - shared_with_entity boolean column (default: false)
#   - user_id OR created_by_id column (for ownership)
#
# Usage:
#   class LandingPage < ApplicationRecord
#     include EntityShareable
#     self.owner_foreign_key = :user_id  # default is :created_by_id
#   end
#
# Provides:
#   - visible_to_user(user) scope: returns user's own assets + entity-shared assets
#   - share_with_entity! / make_private! instance methods
#   - shared? / private? helpers
#
module EntityShareable
  extend ActiveSupport::Concern

  included do
    # Subclasses can override this if their owner FK is named differently
    class_attribute :owner_foreign_key, default: :created_by_id

    scope :shared, -> { where(shared_with_entity: true) }
    scope :not_shared, -> { where(shared_with_entity: false) }

    # Core scope: user's own assets + entity-shared assets from the same entity
    scope :visible_to_user, ->(user) {
      return none unless user

      fk = owner_foreign_key
      table = table_name

      where(
        "(#{table}.#{fk} = :uid) OR " \
        "(#{table}.entity_id = :eid AND #{table}.shared_with_entity = true)",
        uid: user.id, eid: user.entity_id
      )
    }
  end

  # Share this asset with the entire entity
  def share_with_entity!
    update!(shared_with_entity: true)
  end

  # Make this asset private (only visible to creator)
  def make_private!
    update!(shared_with_entity: false)
  end

  def shared?
    shared_with_entity?
  end

  def private_asset?
    !shared_with_entity?
  end

  # Check if a specific user can see this asset
  def visible_to_user?(user)
    return false unless user

    owner_id = send(self.class.owner_foreign_key)
    owner_id == user.id || (entity_id == user.entity_id && shared_with_entity?)
  end
end
