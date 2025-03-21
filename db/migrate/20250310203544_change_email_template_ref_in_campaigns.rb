class ChangeEmailTemplateRefInCampaigns < ActiveRecord::Migration[8.0]
  def change
    change_column_null :campaigns, :email_template_id, true
  end
end
