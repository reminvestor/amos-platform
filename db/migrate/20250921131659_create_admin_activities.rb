class CreateAdminActivities < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_activities do |t|
      t.belongs_to :admin_user, null: false, foreign_key: true
      t.string :action
      t.string :resource_type
      t.string :resource_id
      t.text :details
      t.string :ip_address
      t.text :user_agent

      t.timestamps
    end
  end
end
