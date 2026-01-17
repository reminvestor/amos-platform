class FixQuickbooksApiUrl < ActiveRecord::Migration[7.1]
  def up
    # Fix the QuickBooks Integration api_base_url to include /v3
    execute <<-SQL
      UPDATE integrations 
      SET api_base_url = 'https://quickbooks.api.intuit.com/v3'
      WHERE slug = 'quickbooks' 
        AND (api_base_url = 'https://quickbooks.api.intuit.com' 
             OR api_base_url = 'https://sandbox-quickbooks.api.intuit.com')
    SQL

    # Fix the OauthConfiguration test_endpoint to remove leading slash
    execute <<-SQL
      UPDATE oauth_configurations 
      SET test_endpoint = 'company/{company_id}/companyinfo/{company_id}'
      WHERE integration_id = (SELECT id FROM integrations WHERE slug = 'quickbooks')
        AND test_endpoint LIKE '/%'
    SQL

    puts "✅ Fixed QuickBooks api_base_url and test_endpoint"
  end

  def down
    # Revert to original values (sandbox for safety)
    execute <<-SQL
      UPDATE integrations 
      SET api_base_url = 'https://sandbox-quickbooks.api.intuit.com/v3'
      WHERE slug = 'quickbooks'
    SQL

    execute <<-SQL
      UPDATE oauth_configurations 
      SET test_endpoint = '/company/{company_id}/companyinfo/{company_id}'
      WHERE integration_id = (SELECT id FROM integrations WHERE slug = 'quickbooks')
    SQL
  end
end
