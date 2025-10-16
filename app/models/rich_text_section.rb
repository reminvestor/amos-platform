class RichTextSection < ApplicationRecord
  belongs_to :landing_page
  has_rich_text :content

  validates :section_type, :section_index, presence: true
end
