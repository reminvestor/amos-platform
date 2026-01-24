# frozen_string_literal: true

# DesignPlan stores the plan/blueprint for a landing page or website
# before it's actually built. This supports the "Plan → Build" workflow.
#
# Status flow:
#   draft → building → completed
#                   ↘ failed
#
class DesignPlan < ApplicationRecord
  belongs_to :entity
  belongs_to :user
  belongs_to :landing_page, optional: true

  validates :name, presence: true
  validates :design_type, presence: true, inclusion: { in: %w[landing_page website portfolio single_page] }
  validates :status, presence: true, inclusion: { in: %w[draft building completed failed] }

  scope :drafts, -> { where(status: 'draft') }
  scope :recent, -> { order(created_at: :desc) }

  # Convenience method to get section names
  def section_names
    plan_data.dig('sections')&.map { |s| s['name'] } || []
  end

  # Get color scheme
  def color_scheme
    plan_data['color_scheme'] || {}
  end

  # Get style
  def style
    plan_data['style'] || 'Modern'
  end

  # Summary for display
  def summary
    sections = plan_data['sections'] || []
    {
      section_count: sections.count,
      sections: section_names,
      style: style,
      primary_color: color_scheme['primary'],
      layout: plan_data['layout'] || 'single-column'
    }
  end
end
