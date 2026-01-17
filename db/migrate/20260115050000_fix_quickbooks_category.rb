# frozen_string_literal: true

class FixQuickbooksCategory < ActiveRecord::Migration[8.0]
  def up
    # QuickBooks is accounting software, not a payment processor
    # Changing category so list_connections with integration_type: "accounting" works
    execute <<~SQL
      UPDATE integrations 
      SET category = 'accounting' 
      WHERE slug = 'quickbooks' AND category = 'payment'
    SQL

    puts "✅ Updated QuickBooks category from 'payment' to 'accounting'"
  end

  def down
    execute <<~SQL
      UPDATE integrations 
      SET category = 'payment' 
      WHERE slug = 'quickbooks' AND category = 'accounting'
    SQL
  end
end

