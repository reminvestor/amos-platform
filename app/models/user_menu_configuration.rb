# UserMenuConfiguration
#
# Stores per-space menu visibility preferences for each user.
# Allows users to customize which features appear in their sidebar.
#
class UserMenuConfiguration < ApplicationRecord
  belongs_to :user

  # Validations
  validates :space, presence: true, inclusion: { in: SpaceDefinition::ALL_SPACES }
  validates :user_id, uniqueness: { scope: :space }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # Check if an item is visible
  # Items are OFF by default - only visible if explicitly in visible_items
  def item_visible?(item_slug)
    return false if hidden_items.include?(item_slug.to_s)
    visible_items.include?(item_slug.to_s)
  end

  # Check if an item is pinned
  def item_pinned?(item_slug)
    pinned_items.include?(item_slug.to_s)
  end

  # Show an item
  def show_item(item_slug)
    self.visible_items = (visible_items + [item_slug.to_s]).uniq
    self.hidden_items = hidden_items - [item_slug.to_s]
    save
  end

  # Hide an item
  def hide_item(item_slug)
    self.hidden_items = (hidden_items + [item_slug.to_s]).uniq
    self.visible_items = visible_items - [item_slug.to_s]
    self.pinned_items = pinned_items - [item_slug.to_s]
    save
  end

  # Pin an item
  def pin_item(item_slug)
    show_item(item_slug) # Ensure it's visible
    self.pinned_items = (pinned_items + [item_slug.to_s]).uniq
    save
  end

  # Unpin an item
  def unpin_item(item_slug)
    self.pinned_items = pinned_items - [item_slug.to_s]
    save
  end

  # Reset to space defaults
  def reset_to_defaults!
    space_def = SpaceDefinition.find_by(slug: space)
    return unless space_def

    update!(
      visible_items: space_def.default_menu_items,
      hidden_items: [],
      pinned_items: []
    )
  end

  # Class method to get or create config for a user and space
  def self.for_user_space(user, space_slug)
    find_or_create_by(user: user, space: space_slug.to_s)
  end

  private

  def set_defaults
    self.visible_items ||= []
    self.pinned_items ||= []
    self.hidden_items ||= []
  end
end
