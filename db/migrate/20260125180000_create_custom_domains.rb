# frozen_string_literal: true

class CreateCustomDomains < ActiveRecord::Migration[8.0]
  def change
    create_table :custom_domains do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      
      # Domain info
      t.string :domain_name, null: false
      t.string :subdomain  # Optional subdomain (e.g., "app" for app.example.com)
      
      # Web publishing verification
      t.string :cname_target, null: false  # e.g., "abc123.custom.amoslabs.co"
      t.string :verification_token
      t.string :web_status, default: 'pending'  # pending, verifying, verified, failed
      t.datetime :web_verified_at
      
      # SSL certificate
      t.string :ssl_status, default: 'pending'  # pending, provisioning, active, failed
      t.string :ssl_certificate_arn  # AWS ACM certificate ARN
      t.datetime :ssl_provisioned_at
      
      # Email sending (SES) verification
      t.string :email_status, default: 'pending'  # pending, verifying, verified, failed
      t.string :ses_identity_arn
      t.datetime :email_verified_at
      
      # DKIM/SPF/DMARC records (stored for reference)
      t.jsonb :dns_records, default: {}  # { dkim: [...], spf: "...", dmarc: "...", cname: "..." }
      
      # Connection to GoDaddy (if using integration)
      t.references :connection, foreign_key: true  # GoDaddy connection for auto-DNS
      t.boolean :auto_dns_configured, default: false
      
      # Publishing settings
      t.boolean :is_primary, default: false  # Primary domain for this entity
      t.boolean :redirect_www, default: true  # Redirect www to root or vice versa
      
      # Metadata
      t.jsonb :metadata, default: {}
      t.string :last_error
      
      t.timestamps
    end
    
    add_index :custom_domains, :domain_name, unique: true
    add_index :custom_domains, [:entity_id, :is_primary]
    add_index :custom_domains, :cname_target, unique: true
    add_index :custom_domains, :web_status
    add_index :custom_domains, :email_status
    
    # Add custom_domain reference to publishable models
    add_reference :landing_pages, :custom_domain, foreign_key: true
    add_reference :websites, :custom_domain, foreign_key: true
    add_reference :module_canvases, :custom_domain, foreign_key: true
  end
end
