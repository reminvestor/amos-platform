# frozen_string_literal: true

# Auditable concern for logging changes to important models
# Automatically creates AdminActivity records when models are created or updated
module Auditable
  extend ActiveSupport::Concern

  included do
    after_create :log_creation
    after_update :log_update
  end

  private

  # Log creation of the record
  def log_creation
    return unless should_log?

    AdminActivity.create!(
      admin_user: current_admin_user,
      action: 'create',
      resource_type: self.class.name,
      resource_id: self.id,
      details: build_creation_details
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log creation for #{self.class.name}##{self.id}: #{e.message}"
  end

  # Log update of the record
  def log_update
    return unless should_log?
    return unless saved_changes.any?

    AdminActivity.create!(
      admin_user: current_admin_user,
      action: 'update',
      resource_type: self.class.name,
      resource_id: self.id,
      details: build_update_details
    )
  rescue StandardError => e
    Rails.logger.error "Failed to log update for #{self.class.name}##{self.id}: #{e.message}"
  end

  # Check if we should log this action
  def should_log?
    # Only log if we have an admin user in the current context
    # Skip logging for system-generated changes
    current_admin_user.present?
  end

  # Get the current admin user from the request context
  def current_admin_user
    # Try to get admin user from Current (Rails 5.2+ thread-safe current attributes)
    return Current.admin_user if defined?(Current) && Current.respond_to?(:admin_user)

    # Fallback: try to get from RequestStore if available
    if defined?(RequestStore) && RequestStore.store[:current_admin_user]
      return RequestStore.store[:current_admin_user]
    end

    nil
  end

  # Build details hash for creation log
  def build_creation_details
    {
      attributes: serializable_attributes,
      timestamp: Time.current.iso8601
    }.to_json
  end

  # Build details hash for update log
  def build_update_details
    {
      changes: serializable_changes,
      previous_values: previous_values_from_changes,
      new_values: new_values_from_changes,
      timestamp: Time.current.iso8601
    }.to_json
  end

  # Get serializable version of attributes (excluding sensitive data)
  def serializable_attributes
    attrs = attributes.dup
    # Remove sensitive fields if present
    attrs.delete('password')
    attrs.delete('password_digest')
    attrs
  end

  # Get serializable version of changes
  def serializable_changes
    changes = saved_changes.dup
    # Remove sensitive fields if present
    changes.delete('password')
    changes.delete('password_digest')
    changes
  end

  # Extract previous values from saved_changes
  def previous_values_from_changes
    saved_changes.transform_values { |change| change[0] }
  end

  # Extract new values from saved_changes
  def new_values_from_changes
    saved_changes.transform_values { |change| change[1] }
  end
end
