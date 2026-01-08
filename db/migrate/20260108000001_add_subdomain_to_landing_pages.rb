# frozen_string_literal: true

class AddSubdomainToLandingPages < ActiveRecord::Migration[8.0]
  def change
    add_column :landing_pages, :subdomain, :string

    # Partial unique index - only enforces uniqueness for non-null values
    # This allows multiple draft pages without subdomains while ensuring
    # published pages have unique subdomains
    add_index :landing_pages, :subdomain, unique: true, where: "subdomain IS NOT NULL"
  end
end
