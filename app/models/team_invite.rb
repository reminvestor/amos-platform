# frozen_string_literal: true

class TeamInvite < ApplicationRecord
  belongs_to :entity
  belongs_to :invited_by, class_name: 'User'

  # Validations
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :role, presence: true, inclusion: { in: %w[admin member] }
  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true
  validate :email_not_already_member, on: :create

  # Scopes
  scope :pending, -> { where(status: 'pending').where('expires_at > ?', Time.current) }
  scope :expired, -> { where(status: 'pending').where('expires_at <= ?', Time.current) }

  # Accept the invitation
  def accept!(user)
    return false if expired?
    return false if status != 'pending'

    transaction do
      # Add user to entity
      EntityUser.create!(
        entity: entity,
        user: user,
        role: role
      )

      # Update user's default entity if not set
      user.update!(entity: entity) if user.entity.nil?

      # Mark invite as accepted
      update!(
        status: 'accepted',
        accepted_at: Time.current
      )
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  def decline!
    update!(
      status: 'declined',
      declined_at: Time.current
    )
  end

  def expired?
    expires_at <= Time.current
  end

  def pending?
    status == 'pending' && !expired?
  end

  private

  def email_not_already_member
    existing_user = User.find_by(email: email)
    return unless existing_user

    if entity.users.include?(existing_user)
      errors.add(:email, 'is already a member of this team')
    end
  end
end
