class AddEmailTemplateRefToCampaigns < ActiveRecord::Migration[8.0]
  def change
    add_reference :campaigns, :email_template, null: false, foreign_key: true
  end
end
