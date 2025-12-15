class UserNote < ApplicationRecord
  belongs_to :user

  validates :title, presence: true

  # Colors for note cards
  COLORS = %w[default blue green yellow orange red purple pink].freeze

  validates :color, inclusion: { in: COLORS }, allow_nil: true

  scope :active, -> { where(archived: false) }
  scope :archived, -> { where(archived: true) }
  scope :pinned, -> { where(pinned: true) }
  scope :recent, -> { order(updated_at: :desc) }
  scope :by_color, ->(color) { where(color: color) }

  def archive!
    update!(archived: true, archived_at: Time.current)
  end

  def unarchive!
    update!(archived: false, archived_at: nil)
  end

  def toggle_pin!
    update!(pinned: !pinned)
  end

  def color_class
    case color
    when 'blue' then 'note-blue'
    when 'green' then 'note-green'
    when 'yellow' then 'note-yellow'
    when 'orange' then 'note-orange'
    when 'red' then 'note-red'
    when 'purple' then 'note-purple'
    when 'pink' then 'note-pink'
    else 'note-default'
    end
  end
end
