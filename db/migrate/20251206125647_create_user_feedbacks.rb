class CreateUserFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :user_feedbacks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Polymorphic association - what is being rated?
      t.string :feedbackable_type, null: false
      t.bigint :feedbackable_id, null: false
      
      # The feedback itself
      t.integer :rating, null: false  # -1 (thumbs down), 0 (neutral), 1 (thumbs up)
      t.text :comment                 # Optional user comment
      t.string :feedback_type         # 'accuracy', 'helpfulness', 'speed', 'overall'
      
      # Context
      t.string :session_id            # Scout session where feedback was given
      t.jsonb :metadata, default: {}  # Additional context (tool used, agent used, etc.)
      
      t.timestamps
    end

    # Indexes for efficient queries
    add_index :user_feedbacks, [:feedbackable_type, :feedbackable_id], name: 'idx_user_feedbacks_feedbackable'
    add_index :user_feedbacks, [:user_id, :created_at]
    add_index :user_feedbacks, [:entity_id, :created_at]
    add_index :user_feedbacks, :rating
    add_index :user_feedbacks, :feedback_type
    add_index :user_feedbacks, :session_id
    
    # Prevent duplicate feedback on same item from same user (within session)
    add_index :user_feedbacks, [:user_id, :feedbackable_type, :feedbackable_id, :session_id], 
              unique: true, 
              name: 'idx_user_feedbacks_unique_per_session',
              where: 'session_id IS NOT NULL'
  end
end

