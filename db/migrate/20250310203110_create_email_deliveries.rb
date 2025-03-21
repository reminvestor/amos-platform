class CreateEmailDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :email_deliveries do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :status
      t.datetime :sent_at
      t.datetime :opened_at
      t.datetime :clicked_at
      t.references :email_template, null: false, foreign_key: true

      t.timestamps
    end
  end
end
