class RagStore < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :entity, optional: true

  # Validations
  validates :name, presence: true
  validates :app_name, presence: true
  validates :pinecone_index, presence: true
  validates :pinecone_namespace, presence: true
  validates :status, presence: true
  validates :status, inclusion: { in: %w[building active failed archived] }

  # Scopes
  scope :active, -> { where(status: "active") }
  scope :by_app, ->(app_name) { where(app_name: app_name) }

  # Default values
  after_initialize :set_defaults, if: :new_record?

  # Get the most recent RAG store for an app
  def self.latest_for_app(app_name)
    where(app_name: app_name, status: "active")
      .order(created_at: :desc)
      .first
  end

  # Archive this RAG store
  def archive!
    update!(status: "archived")
  end

  # Check if the store is ready for queries
  def ready?
    status == "active" && chunk_count.to_i > 0
  end

  # Status helper methods
  def active?
    status == "active"
  end

  def building?
    status == "building"
  end

  def failed?
    status == "failed"
  end

  def archived?
    status == "archived"
  end

  private

  def set_defaults
    self.status ||= "building"
    self.chunk_count ||= 0
    self.metadata ||= {}
  end
end