class CreateAdminUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :admin_users do |t|
      t.string :email
      t.string :password_digest
      t.string :first_name
      t.string :last_name
      t.integer :role, null: false, default: 0
      t.datetime :last_login_at
      t.integer :login_count, null: false, default: 0
      t.integer :failed_login_attempts, null: false, default: 0
      t.datetime :locked_at

      t.timestamps
    end
    add_index :admin_users, :email, unique: true
  end
end
