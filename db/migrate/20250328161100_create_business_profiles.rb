class CreateBusinessProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :business_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name
      t.string :industry
      t.text :description
      t.integer :founded_year
      t.string :website
      t.text :values
      t.text :target_audience
      t.text :tone_of_voice
      t.jsonb :knowledge_base

      t.timestamps
    end
  end
end
