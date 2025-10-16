class EmailTemplate < ApplicationRecord
  belongs_to :user
  belongs_to :entity

  # Associations
  has_many :campaigns
  has_many :email_deliveries, dependent: :nullify

  # Validations
  validates :name, presence: true
  validates :subject, presence: true
  validates :body, presence: true

  # Broadcast changes to refresh UI in real-time
  after_create_commit lambda { broadcast_prepend_to_list }
  after_update_commit lambda { broadcast_replace_to_list }
  after_destroy_commit lambda { broadcast_remove_to_list }

  # Methods for AI integration
  def generate_content(prompt = nil)
    # This will be implemented later with AI integration
    # For now, we'll return a placeholder
    "This is where AI-generated content will go based on #{prompt || 'default prompt'}"
  end

  private

  def broadcast_prepend_to_list
    broadcast_prepend_to(
      "entity_#{entity_id}_email_templates",
      target: "email-templates-tbody",
      partial: "email_templates/email_template_row",
      locals: { template: self }
    )
  end

  def broadcast_replace_to_list
    broadcast_replace_to(
      "entity_#{entity_id}_email_templates",
      target: "email_template_#{id}",
      partial: "email_templates/email_template_row",
      locals: { template: self }
    )
  end

  def broadcast_remove_to_list
    broadcast_remove_to(
      "entity_#{entity_id}_email_templates",
      target: "email_template_#{id}"
    )
  end
end
