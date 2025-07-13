class CreateBusinessInsights < ActiveRecord::Migration[8.0]
  def change
    create_table :business_insights do |t|
      t.references :entity, null: false, foreign_key: true
      t.string :insight_type
      t.jsonb :content
      t.float :confidence_score
      t.references :source_conversation, null: false, foreign_key: { to_table: :scout_conversations }

      t.timestamps
    end
  end
end
