class CreateVoiceAssistantSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :voice_assistant_settings do |t|
      t.string :key
      t.text :value
      t.string :setting_type
      t.text :description

      t.timestamps
    end
    add_index :voice_assistant_settings, :key, unique: true
  end
end
