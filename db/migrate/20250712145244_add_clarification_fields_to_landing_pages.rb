class AddClarificationFieldsToLandingPages < ActiveRecord::Migration[8.0]
  def change
    add_column :landing_pages, :clarification_questions, :text
    add_column :landing_pages, :clarification_answers, :text
  end
end
