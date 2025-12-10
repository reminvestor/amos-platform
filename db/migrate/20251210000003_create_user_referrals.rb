class CreateUserReferrals < ActiveRecord::Migration[8.0]
  def change
    create_table :user_referrals do |t|
      t.references :referrer, null: false, foreign_key: { to_table: :users }
      t.references :referred_user, foreign_key: { to_table: :users }, null: true
      t.string :referred_email, null: false
      t.string :token, null: false
      t.integer :status, default: 0, null: false  # 0=pending, 1=signed_up, 2=expired
      t.integer :tokens_awarded, default: 0
      t.datetime :email_sent_at
      t.datetime :signed_up_at
      t.datetime :expires_at

      t.timestamps
    end

    add_index :user_referrals, :token, unique: true
    add_index :user_referrals, [:referrer_id, :referred_email], unique: true
    add_index :user_referrals, :referred_email
    add_index :user_referrals, :status
  end
end
