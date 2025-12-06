# frozen_string_literal: true

# == Schema Information
#
# Table name: user_favorites
#
#  id               :bigint           not null, primary key
#  user_id          :bigint           not null
#  entity_id        :bigint           not null
#  favoritable_type :string           not null
#  favoritable_id   :bigint           not null
#  nickname         :string
#  notes            :text
#  priority         :integer          default(0)
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
class UserFavorite < ApplicationRecord
  # ============================================
  # ASSOCIATIONS
  # ============================================
  
  belongs_to :user
  belongs_to :entity
  belongs_to :favoritable, polymorphic: true

  # ============================================
  # VALIDATIONS
  # ============================================
  
  VALID_FAVORITABLE_TYPES = %w[
    AgentPlugin
    ToolDefinition
    Integration
  ].freeze

  validates :favoritable_type, presence: true, inclusion: { 
    in: VALID_FAVORITABLE_TYPES,
    message: "must be one of: #{VALID_FAVORITABLE_TYPES.join(', ')}"
  }
  validates :nickname, length: { maximum: 100 }, allow_blank: true
  validates :notes, length: { maximum: 500 }, allow_blank: true
  validates :user_id, uniqueness: { 
    scope: [:favoritable_type, :favoritable_id],
    message: "has already favorited this item"
  }

  # ============================================
  # SCOPES
  # ============================================
  
  scope :agents, -> { where(favoritable_type: 'AgentPlugin') }
  scope :tools, -> { where(favoritable_type: 'ToolDefinition') }
  scope :integrations, -> { where(favoritable_type: 'Integration') }
  scope :by_priority, -> { order(priority: :desc, created_at: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  # ============================================
  # CLASS METHODS
  # ============================================
  
  # Get all favorited IDs for a user by type
  def self.favorited_ids_for(user, type)
    where(user: user, favoritable_type: type).pluck(:favoritable_id)
  end

  # Check if user has favorited something
  def self.favorited?(user, favoritable)
    exists?(user: user, favoritable: favoritable)
  end

  # Toggle favorite (create or destroy)
  def self.toggle!(user:, entity:, favoritable:)
    existing = find_by(user: user, favoritable: favoritable)
    
    if existing
      existing.destroy
      { favorited: false, message: "Removed from favorites" }
    else
      create!(user: user, entity: entity, favoritable: favoritable)
      { favorited: true, message: "Added to favorites" }
    end
  end

  # ============================================
  # INSTANCE METHODS
  # ============================================
  
  def display_name
    nickname.presence || favoritable.try(:name) || "Unnamed"
  end
end

