class CreateScoutPersonalities < ActiveRecord::Migration[7.1]
  def change
    create_table :scout_personalities do |t|
      t.references :entity, null: false, foreign_key: true
      
      # Core personality traits (scale 1-10)
      t.integer :formality, default: 5        # 1=casual, 10=very formal
      t.integer :verbosity, default: 4        # 1=terse, 10=verbose
      t.integer :proactivity, default: 7      # 1=passive, 10=proactive
      t.integer :humor, default: 3            # 1=serious, 10=playful
      t.integer :technicality, default: 5     # 1=simple, 10=technical
      
      # Communication preferences
      t.string :greeting_style, default: 'warm'  # warm, professional, casual, minimal
      t.string :response_length, default: 'concise'  # brief, concise, detailed, comprehensive
      t.boolean :use_emojis, default: true
      t.boolean :show_thinking, default: false  # Show "thinking..." or tool usage
      
      # Custom personality elements
      t.string :name, default: 'Scout'  # Can be renamed per entity
      t.text :custom_instructions  # Additional personality instructions
      t.text :phrases  # JSON array of preferred phrases/expressions
      t.text :avoid_phrases  # JSON array of phrases to avoid
      
      # Meta
      t.boolean :active, default: true
      
      t.timestamps
    end
    
    # Note: entity_id index already created by references, just need to make it unique
    remove_index :scout_personalities, :entity_id
    add_index :scout_personalities, :entity_id, unique: true
  end
end
