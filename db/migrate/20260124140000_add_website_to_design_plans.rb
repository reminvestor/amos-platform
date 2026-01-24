# frozen_string_literal: true

class AddWebsiteToDesignPlans < ActiveRecord::Migration[7.1]
  def change
    add_reference :design_plans, :website, null: true, foreign_key: true
  end
end
