class CreateLandingPageChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :landing_page_chat_messages do |t|
      t.references :landing_page, null: false, foreign_key: true
      t.text :content
      t.string :role
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
