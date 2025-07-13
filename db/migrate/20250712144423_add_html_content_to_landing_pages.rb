class AddHtmlContentToLandingPages < ActiveRecord::Migration[8.0]
  def change
    add_column :landing_pages, :html_content, :text
  end
end
