class CreateUserFavorites < ActiveRecord::Migration[8.0]
  def change
    create_table :user_favorites do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Polymorphic association - what is being favorited?
      t.string :favoritable_type, null: false
      t.bigint :favoritable_id, null: false
      
      # Optional notes/tags from user
      t.string :nickname              # User's custom name for this favorite
      t.text :notes                   # Why they favorited it
      t.integer :priority, default: 0 # User can order their favorites
      
      t.timestamps
    end

    # Indexes for efficient queries
    add_index :user_favorites, [:favoritable_type, :favoritable_id], name: 'idx_user_favorites_favoritable'
    add_index :user_favorites, [:user_id, :favoritable_type], name: 'idx_user_favorites_by_type'
    add_index :user_favorites, :priority
    
    # Prevent duplicate favorites
    add_index :user_favorites, [:user_id, :favoritable_type, :favoritable_id], 
              unique: true, 
              name: 'idx_user_favorites_unique'
  end
end

