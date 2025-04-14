class CreateRichTextSections < ActiveRecord::Migration[8.0]
  def change
    create_table :rich_text_sections do |t|
      t.string :title
      t.string :section_type
      t.integer :section_index
      t.string :image_url
      t.references :landing_page, null: false, foreign_key: true

      t.timestamps
    end
  end
end
