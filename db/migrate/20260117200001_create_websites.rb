# frozen_string_literal: true

class CreateWebsites < ActiveRecord::Migration[7.1]
  def change
    # ============================================
    # WEBSITES - Multi-page sites with shared layout
    # ============================================
    create_table :websites do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :application_plan, foreign_key: true  # Optional link to plan
      
      # Basic info
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      
      # Status: draft, published, archived
      t.string :status, null: false, default: 'draft'
      
      # Theme & Styling
      t.string :theme, default: 'modern'
      t.jsonb :theme_config, null: false, default: {}
      # { 
      #   primary_color: '#007bff',
      #   secondary_color: '#6c757d',
      #   font_family: 'Inter',
      #   header_style: 'sticky',
      #   footer_style: 'minimal'
      # }
      
      # Shared Layout HTML
      t.text :header_html
      t.text :footer_html
      t.text :custom_css
      t.text :custom_js
      
      # SEO & Meta
      t.string :meta_title
      t.text :meta_description
      t.string :favicon_url
      t.string :og_image_url
      
      # Domain Configuration
      t.string :subdomain           # mysite.amoslabs.com
      t.string :custom_domain       # www.mysite.com
      t.boolean :ssl_enabled, default: true
      
      # Features
      t.jsonb :features, null: false, default: []
      # ['search', 'categories', 'comments', 'analytics']
      
      # Analytics
      t.string :google_analytics_id
      t.jsonb :tracking_config, default: {}
      
      # Publishing
      t.datetime :published_at
      t.datetime :last_built_at
      
      t.timestamps
    end
    
    add_index :websites, :slug
    add_index :websites, :subdomain, unique: true
    add_index :websites, :custom_domain, unique: true
    add_index :websites, [:entity_id, :slug], unique: true
    add_index :websites, :status
    
    # ============================================
    # WEBSITE PAGES - Individual pages within a website
    # ============================================
    create_table :website_pages do |t|
      t.references :website, null: false, foreign_key: true
      t.references :entity, null: false, foreign_key: true
      
      # Page info
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      
      # Content
      t.text :html_content
      t.jsonb :content_blocks, null: false, default: []
      # [{ type: 'hero', data: {...} }, { type: 'features', data: {...} }]
      
      # Template & Layout
      t.string :template, default: 'content'
      # Templates: homepage, content, list, detail, form, custom
      t.boolean :use_website_layout, default: true
      t.text :custom_header_html
      t.text :custom_footer_html
      
      # Page type flags
      t.boolean :is_homepage, default: false
      t.boolean :is_dynamic, default: false  # Has dynamic content from module
      
      # Dynamic content binding
      t.references :app_module, foreign_key: true  # If page shows module data
      t.string :module_view_type  # list, detail, form
      t.jsonb :module_config, default: {}  # Filters, display options
      
      # SEO
      t.string :meta_title
      t.text :meta_description
      t.string :og_image_url
      
      # Navigation
      t.boolean :show_in_nav, default: true
      t.integer :nav_order, default: 0
      t.string :nav_label  # Override name in nav
      
      # Access control
      t.boolean :requires_auth, default: false
      t.jsonb :access_roles, default: []  # Which roles can view
      
      # Status
      t.string :status, null: false, default: 'draft'
      t.datetime :published_at
      
      t.timestamps
    end
    
    add_index :website_pages, [:website_id, :slug], unique: true
    add_index :website_pages, [:website_id, :is_homepage]
    add_index :website_pages, :template
    add_index :website_pages, :status
    
    # ============================================
    # WEB APPS - Website + Modules + Auth
    # ============================================
    create_table :web_apps do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :created_by, null: false, foreign_key: { to_table: :users }
      t.references :application_plan, foreign_key: true
      t.references :website, foreign_key: true  # The public-facing website
      
      # Basic info
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      
      # Status
      t.string :status, null: false, default: 'draft'
      
      # Authentication configuration
      t.boolean :requires_auth, default: true
      t.jsonb :auth_config, null: false, default: {}
      # {
      #   methods: ['email', 'google', 'magic_link'],
      #   allow_registration: true,
      #   require_email_verification: true,
      #   session_timeout: 3600
      # }
      
      # User roles
      t.jsonb :roles, null: false, default: []
      # [{ name: 'admin', permissions: [...] }, { name: 'user', ... }]
      
      # Connected modules
      t.jsonb :module_config, null: false, default: {}
      # {
      #   'knowledge_base' => { public: true, create: false },
      #   'submissions' => { public: false, create: true }
      # }
      
      # Branding
      t.string :logo_url
      t.string :primary_color
      t.jsonb :branding, default: {}
      
      # Domain
      t.string :subdomain
      t.string :custom_domain
      
      # Features
      t.jsonb :features, null: false, default: []
      # ['user_dashboard', 'notifications', 'file_uploads']
      
      # Analytics
      t.integer :user_count, default: 0
      t.integer :monthly_active_users, default: 0
      t.datetime :last_activity_at
      
      t.timestamps
    end
    
    add_index :web_apps, [:entity_id, :slug], unique: true
    add_index :web_apps, :subdomain, unique: true
    add_index :web_apps, :custom_domain, unique: true
    add_index :web_apps, :status
    
    # ============================================
    # WEB APP MODULES - Link between web app and modules
    # ============================================
    create_table :web_app_modules do |t|
      t.references :web_app, null: false, foreign_key: true
      t.references :app_module, null: false, foreign_key: true
      
      # How this module is exposed in the web app
      t.boolean :is_public, default: false  # Visible without auth
      t.boolean :allow_create, default: false  # Users can create records
      t.boolean :allow_edit, default: false
      t.boolean :allow_delete, default: false
      
      # Which fields are visible/editable
      t.jsonb :visible_fields, default: []
      t.jsonb :editable_fields, default: []
      
      # Role-based access
      t.jsonb :role_permissions, default: {}
      # { 'admin' => { create: true, edit: true }, 'user' => { create: false } }
      
      # Display configuration
      t.string :list_view_type, default: 'table'  # table, grid, cards
      t.integer :nav_order, default: 0
      t.string :nav_icon
      
      t.timestamps
    end
    
    add_index :web_app_modules, [:web_app_id, :app_module_id], unique: true
  end
end

