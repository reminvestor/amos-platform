# UserSpacePreference
#
# Tracks which space/mode a user is currently in and their per-space settings.
#
# THREE MODE ARCHITECTURE:
# - Personal: Private thinking space
# - Operations: Business HQ (merged Work + Team)
# - Design: Creation studio
#
class UserSpacePreference < ApplicationRecord
  belongs_to :user

  # Validations
  validates :user_id, uniqueness: true
  validates :active_space, inclusion: { in: SpaceDefinition::ALL_SPACES }

  # Callbacks
  after_initialize :set_defaults, if: :new_record?

  # Map legacy space slugs to new architecture
  def self.normalize_space(space_slug)
    case space_slug.to_s
    when 'work', 'team' then 'operations'
    else space_slug.to_s
    end
  end

  # Get the active space definition
  def active_space_definition
    # Map legacy spaces to new ones
    normalized = self.class.normalize_space(active_space)
    SpaceDefinition.find_by(slug: normalized) || SpaceDefinition.find_by(slug: active_space)
  end

  # Switch to a different space
  def switch_to(space_slug)
    normalized = self.class.normalize_space(space_slug)
    
    # Check if valid
    return false unless SpaceDefinition::ALL_SPACES.include?(normalized) || 
                        SpaceDefinition::ALL_SPACES.include?(space_slug.to_s)
    
    # Enable if not already enabled
    enable_space(normalized) unless space_enabled?(normalized)
    
    update(active_space: normalized)
  end

  # Check if a space is enabled for this user
  def space_enabled?(space_slug)
    normalized = self.class.normalize_space(space_slug)
    enabled_spaces.include?(normalized) || enabled_spaces.include?(space_slug.to_s)
  end

  # Enable a space
  def enable_space(space_slug)
    normalized = self.class.normalize_space(space_slug)
    return false unless SpaceDefinition::ALL_SPACES.include?(normalized) ||
                        SpaceDefinition::ALL_SPACES.include?(space_slug.to_s)
    
    self.enabled_spaces = (enabled_spaces + [normalized]).uniq
    save
  end

  # Disable a space
  def disable_space(space_slug)
    normalized = self.class.normalize_space(space_slug)
    return false if normalized == 'operations' # Operations space cannot be disabled (primary business space)
    
    self.enabled_spaces = enabled_spaces - [normalized, space_slug.to_s]
    # If disabling current space, switch to operations
    if self.class.normalize_space(active_space) == normalized
      self.active_space = 'operations'
    end
    save
  end

  # Get settings for the current space
  def current_settings
    normalized = self.class.normalize_space(active_space)
    
    # Map to settings column (operations uses the work_settings column for backwards compat)
    settings_key = case normalized
                   when 'operations' then 'work_settings'
                   when 'personal' then 'personal_settings'
                   when 'design' then 'design_settings'
                   else "#{normalized}_settings"
                   end
    
    send(settings_key) rescue {} || {}
  end

  # Update settings for a specific space
  def update_space_settings(space_slug, settings)
    normalized = self.class.normalize_space(space_slug)
    
    settings_key = case normalized
                   when 'operations' then 'work_settings'
                   when 'personal' then 'personal_settings'
                   when 'design' then 'design_settings'
                   else "#{normalized}_settings"
                   end
    
    update(settings_key => settings) rescue false
  end

  # Class method to get or create preferences for a user
  def self.for_user(user)
    find_or_create_by(user: user)
  end

  private

  def set_defaults
    self.active_space ||= 'operations'
    self.enabled_spaces ||= SpaceDefinition::PRIMARY_SPACES
    self.personal_settings ||= {}
    self.work_settings ||= {}  # Used for both work (legacy) and operations
    self.team_settings ||= {}  # Legacy, may be removed later
  end
end
