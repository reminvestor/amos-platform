class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :trackable
  
  # Constants
  ROLES = %w[admin marketer viewer].freeze
  
  # Validations
  validates :first_name, :last_name, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }
  
  # Associations
  has_many :contacts, dependent: :destroy
  has_many :contact_groups, dependent: :destroy
  has_many :email_templates, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  
  # Methods
  def full_name
    "#{first_name} #{last_name}"
  end
  
  def admin?
    role == 'admin'
  end
  
  def marketer?
    role == 'marketer'
  end
  
  def viewer?
    role == 'viewer'
  end
end
