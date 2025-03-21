class Contact < ApplicationRecord
  belongs_to :user
  
  # Many-to-many association with contact groups
  has_and_belongs_to_many :contact_groups
  
  # Validations
  validates :email, presence: true, uniqueness: { scope: :user_id }, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, presence: true
  
  # Status options
  STATUSES = %w[active inactive unsubscribed].freeze
  validates :status, inclusion: { in: STATUSES }, allow_nil: true
  
  # Methods
  def full_name
    "#{first_name} #{last_name}"
  end
end
