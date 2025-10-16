class CreateLandingPageSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :landing_page_submissions do |t|
      t.references :landing_page, null: false, foreign_key: true
      t.references :contact, null: true, foreign_key: true
      t.string :form_type, null: false
      t.jsonb :submission_data, default: {}, null: false
      t.string :source_ip
      t.text :user_agent
      t.datetime :submitted_at, null: false
      t.datetime :processed_at
      t.string :status, default: 'pending', null: false
      t.jsonb :metadata, default: {}, null: false
      t.string :session_id  # For tracking user sessions
      t.string :referrer    # Where they came from

      t.timestamps
    end

    # Indexes for performance
    add_index :landing_page_submissions, :form_type
    add_index :landing_page_submissions, :status
    add_index :landing_page_submissions, :submitted_at
    add_index :landing_page_submissions, [ :landing_page_id, :submitted_at ]
    add_index :landing_page_submissions, [ :contact_id, :submitted_at ]
    add_index :landing_page_submissions, :session_id
  end
end
