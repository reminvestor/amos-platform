class EmailTemplate < ApplicationRecord
  belongs_to :user
  
  # Associations
  has_many :email_deliveries, dependent: :nullify
  
  # Validations
  validates :name, presence: true
  validates :subject, presence: true
  validates :body, presence: true
  
  # Methods for AI integration
  def generate_content(prompt = nil)
    # This will be implemented later with AI integration
    # For now, we'll return a placeholder
    "This is where AI-generated content will go based on #{prompt || 'default prompt'}"
  end
end
