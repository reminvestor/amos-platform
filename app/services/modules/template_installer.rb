# frozen_string_literal: true

# TemplateInstaller
#
# Installs pre-built module templates. Templates are defined as
# structured specifications that the Platform Factory builds from.
#
module Modules
  class TemplateInstaller
    # Available module templates
    TEMPLATES = {
      'inventory_management' => {
        name: 'Inventory Management',
        description: 'Track products, stock levels, reorder points, and suppliers. Get alerts for low stock.',
        icon: 'package',
        requirements: <<~REQ.strip,
          Build an inventory management system with:
          - Products with name, SKU, description, price, and quantity
          - Categories for organizing products
          - Suppliers with contact information
          - Stock level tracking with reorder thresholds
          - Low stock alerts
        REQ
        features: [
          'Product catalog',
          'Category management',
          'Supplier directory',
          'Stock level tracking',
          'Low stock alerts',
          'Inventory reports'
        ]
      },
      'project_management' => {
        name: 'Project Management',
        description: 'Manage projects, tasks, milestones, and team assignments. Kanban board included.',
        icon: 'kanban',
        requirements: <<~REQ.strip,
          Build a project management system with:
          - Projects with name, description, status, start/end dates
          - Tasks with title, description, status, priority, assignee, due date
          - Milestones for tracking major deliverables
          - Team member assignments
          - Kanban board view for tasks
          - Project timeline/Gantt view
        REQ
        features: [
          'Project tracking',
          'Task management',
          'Milestone tracking',
          'Team assignments',
          'Kanban board',
          'Progress reports'
        ]
      },
      'financial_tracking' => {
        name: 'Financial Tracking',
        description: 'Track income, expenses, invoices, and generate financial reports.',
        icon: 'wallet',
        requirements: <<~REQ.strip,
          Build a financial tracking system with:
          - Income entries with amount, category, date, description
          - Expense entries with amount, category, vendor, date, description
          - Categories for organizing transactions
          - Invoice tracking with status, due date, client
          - Monthly/yearly summaries
          - Budget tracking
        REQ
        features: [
          'Income tracking',
          'Expense tracking',
          'Invoice management',
          'Category management',
          'Financial reports',
          'Budget vs actuals'
        ]
      },
      'crm_extension' => {
        name: 'CRM Extension',
        description: 'Enhanced contact management with custom fields and segments.',
        icon: 'users',
        requirements: <<~REQ.strip,
          Extend the existing CRM with:
          - Contact segments for grouping contacts
          - Contact tags for flexible categorization
          - Contact notes with timestamps
          - Interaction history (calls, emails, meetings)
          - Custom field support
        REQ
        features: [
          'Contact segments',
          'Contact tags',
          'Interaction history',
          'Contact notes',
          'Custom fields'
        ]
      },
      'property_management' => {
        name: 'Property Management',
        description: 'Manage properties, tenants, leases, and maintenance requests.',
        icon: 'building',
        requirements: <<~REQ.strip,
          Build a property management system with:
          - Properties with address, type, bedrooms, bathrooms, rent amount
          - Tenants with name, contact info, emergency contact
          - Leases linking tenants to properties with terms
          - Maintenance requests with status, priority, description
          - Rent payment tracking
          - Lease expiry alerts
        REQ
        features: [
          'Property listings',
          'Tenant directory',
          'Lease management',
          'Maintenance requests',
          'Rent tracking',
          'Lease alerts'
        ]
      },
      'support_tickets' => {
        name: 'Support Tickets',
        description: 'Customer support ticketing with SLA tracking and escalation.',
        icon: 'ticket',
        requirements: <<~REQ.strip,
          Build a support ticket system with:
          - Tickets with subject, description, status, priority
          - Customer linking (to contacts)
          - Ticket comments/responses
          - SLA tracking with response time goals
          - Escalation rules
          - Ticket assignment to team members
        REQ
        features: [
          'Ticket creation',
          'Status tracking',
          'Priority levels',
          'SLA monitoring',
          'Team assignment',
          'Response tracking'
        ]
      },
      'employee_directory' => {
        name: 'Employee Directory',
        description: 'Team directory with departments, roles, and org chart.',
        icon: 'contact',
        requirements: <<~REQ.strip,
          Build an employee directory with:
          - Employees with name, email, phone, title, photo
          - Departments with name and manager
          - Teams within departments
          - Manager/report relationships for org chart
          - Employee search and filtering
        REQ
        features: [
          'Employee profiles',
          'Department structure',
          'Team management',
          'Org chart',
          'Search & filter'
        ]
      },
      'event_management' => {
        name: 'Event Management',
        description: 'Plan events, track RSVPs, manage venues and speakers.',
        icon: 'calendar',
        requirements: <<~REQ.strip,
          Build an event management system with:
          - Events with name, description, date, time, location
          - Venues with address, capacity, amenities
          - Speakers/presenters with bio and session assignments
          - RSVP tracking with confirmation status
          - Event schedules/agendas
          - Attendee check-in
        REQ
        features: [
          'Event creation',
          'Venue management',
          'Speaker directory',
          'RSVP tracking',
          'Schedule builder',
          'Check-in'
        ]
      },
      'subscription_billing' => {
        name: 'Subscription Billing',
        description: 'Manage subscriptions, billing cycles, and payment tracking.',
        icon: 'credit-card',
        requirements: <<~REQ.strip,
          Build a subscription billing system with:
          - Subscription plans with name, price, billing cycle
          - Customer subscriptions with status and renewal date
          - Payment history with amount, date, status
          - Subscription upgrades/downgrades
          - Cancellation tracking
          - Revenue reporting
        REQ
        features: [
          'Plan management',
          'Subscription tracking',
          'Payment history',
          'Plan changes',
          'Revenue reports',
          'Renewal alerts'
        ]
      },
      'knowledge_base' => {
        name: 'Knowledge Base',
        description: 'Articles, FAQs, and documentation with search.',
        icon: 'book-open',
        requirements: <<~REQ.strip,
          Build a knowledge base with:
          - Articles with title, content, category, tags
          - Categories for organizing articles
          - FAQ entries with question and answer
          - Full-text search
          - Article versioning
          - View tracking for popular articles
        REQ
        features: [
          'Article management',
          'Categories',
          'FAQ section',
          'Search',
          'Version history',
          'Analytics'
        ]
      }
    }.freeze

    def initialize(entity:, user:)
      @entity = entity
      @user = user
    end

    def install(template_key)
      template = TEMPLATES[template_key]
      return { success: false, error: "Unknown template: #{template_key}" } unless template

      # Check if already installed
      existing = @entity.app_modules.find_by(slug: template_key)
      if existing&.active?
        return { success: false, error: "Module already installed", module: existing }
      end

      # Queue Platform Factory to build it
      result = request_build(template_key, template)

      {
        success: true,
        module_name: template[:name],
        module_slug: result[:module_slug],
        execution_id: result[:execution_id],
        message: "Installing #{template[:name]}...",
        redirect: "module_#{result[:module_slug]}_overview"
      }
    end

    def available_templates
      TEMPLATES.map do |key, template|
        {
          key: key,
          name: template[:name],
          description: template[:description],
          icon: template[:icon],
          features: template[:features],
          installed: @entity.app_modules.exists?(slug: key)
        }
      end
    end

    # Install a customized version of a template
    def install_customized(customized_template)
      # Create a module with the customized schema
      app_module = @entity.app_modules.create!(
        name: customized_template[:name],
        slug: customized_template[:name].parameterize.underscore,
        description: customized_template[:description] || "Customized module",
        status: 'building',
        version: '1.0.0',
        configuration: {
          custom: true,
          original_template: customized_template[:original_template],
          schema: { fields: customized_template[:fields] }
        }
      )

      # Queue Platform Factory to build it with the custom schema
      PlatformFactoryJob.perform_later(
        entity_id: @entity.id,
        module_id: app_module.id,
        schema: {
          'module_name' => customized_template[:name],
          'description' => customized_template[:description],
          'fields' => customized_template[:fields].map(&:stringify_keys)
        }
      )

      { success: true, module: app_module }
    rescue ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    end

    # Get a template's field definitions (for customization preview)
    def template_fields(template_key)
      template = TEMPLATES[template_key]
      return nil unless template

      # Generate default fields based on requirements
      default_fields_for(template_key)
    end

    private

    # Default field definitions for each template
    def default_fields_for(template_key)
      case template_key
      when 'inventory_management'
        inventory_management_fields
      when 'project_management'
        project_management_fields
      when 'financial_tracking'
        financial_tracking_fields
      when 'crm_extension'
        crm_extension_fields
      when 'property_management'
        property_management_fields
      when 'support_tickets'
        support_tickets_fields
      when 'employee_directory'
        employee_directory_fields
      when 'event_management'
        event_management_fields
      when 'subscription_billing'
        subscription_billing_fields
      when 'knowledge_base'
        knowledge_base_fields
      else
        []
      end
    end

    def inventory_management_fields
      [
        { name: 'product_name', field_type: 'string', required: true, description: 'Name of the product' },
        { name: 'sku', field_type: 'string', required: true, description: 'Stock Keeping Unit' },
        { name: 'description', field_type: 'text', required: false, description: 'Product description' },
        { name: 'price', field_type: 'decimal', required: true, description: 'Unit price' },
        { name: 'quantity', field_type: 'integer', required: true, description: 'Current stock level' },
        { name: 'reorder_point', field_type: 'integer', required: false, description: 'Reorder threshold' },
        { name: 'category', field_type: 'string', required: false, description: 'Product category' },
        { name: 'supplier', field_type: 'string', required: false, description: 'Supplier name' }
      ]
    end

    def project_management_fields
      [
        { name: 'project_name', field_type: 'string', required: true, description: 'Name of the project' },
        { name: 'description', field_type: 'text', required: false, description: 'Project description' },
        { name: 'status', field_type: 'string', required: true, description: 'Current status', options: %w[planning active on_hold completed] },
        { name: 'priority', field_type: 'string', required: false, description: 'Priority level', options: %w[low medium high critical] },
        { name: 'start_date', field_type: 'date', required: false, description: 'Start date' },
        { name: 'end_date', field_type: 'date', required: false, description: 'Target end date' },
        { name: 'assignee', field_type: 'string', required: false, description: 'Assigned to' }
      ]
    end

    def financial_tracking_fields
      [
        { name: 'amount', field_type: 'decimal', required: true, description: 'Transaction amount' },
        { name: 'transaction_type', field_type: 'string', required: true, description: 'Income or Expense', options: %w[income expense] },
        { name: 'category', field_type: 'string', required: false, description: 'Category' },
        { name: 'description', field_type: 'text', required: false, description: 'Description' },
        { name: 'transaction_date', field_type: 'date', required: true, description: 'Date of transaction' },
        { name: 'vendor', field_type: 'string', required: false, description: 'Vendor/Client name' },
        { name: 'reference', field_type: 'string', required: false, description: 'Invoice/Reference number' }
      ]
    end

    def crm_extension_fields
      [
        { name: 'segment_name', field_type: 'string', required: true, description: 'Contact segment name' },
        { name: 'tag', field_type: 'string', required: false, description: 'Tag name' },
        { name: 'interaction_type', field_type: 'string', required: false, description: 'Type of interaction', options: %w[call email meeting note] },
        { name: 'interaction_date', field_type: 'datetime', required: false, description: 'When interaction occurred' },
        { name: 'notes', field_type: 'text', required: false, description: 'Notes about the interaction' }
      ]
    end

    def property_management_fields
      [
        { name: 'property_name', field_type: 'string', required: true, description: 'Property identifier' },
        { name: 'address', field_type: 'string', required: true, description: 'Full address' },
        { name: 'property_type', field_type: 'string', required: false, description: 'Type of property', options: %w[apartment house condo commercial] },
        { name: 'bedrooms', field_type: 'integer', required: false, description: 'Number of bedrooms' },
        { name: 'bathrooms', field_type: 'decimal', required: false, description: 'Number of bathrooms' },
        { name: 'rent_amount', field_type: 'decimal', required: false, description: 'Monthly rent' },
        { name: 'status', field_type: 'string', required: true, description: 'Occupancy status', options: %w[available occupied maintenance] }
      ]
    end

    def support_tickets_fields
      [
        { name: 'subject', field_type: 'string', required: true, description: 'Ticket subject' },
        { name: 'description', field_type: 'text', required: true, description: 'Issue description' },
        { name: 'status', field_type: 'string', required: true, description: 'Ticket status', options: %w[open in_progress pending resolved closed] },
        { name: 'priority', field_type: 'string', required: true, description: 'Priority level', options: %w[low medium high urgent] },
        { name: 'assignee', field_type: 'string', required: false, description: 'Assigned agent' },
        { name: 'customer_email', field_type: 'string', required: true, description: 'Customer email' },
        { name: 'due_date', field_type: 'datetime', required: false, description: 'SLA due date' }
      ]
    end

    def employee_directory_fields
      [
        { name: 'full_name', field_type: 'string', required: true, description: 'Employee name' },
        { name: 'email', field_type: 'string', required: true, description: 'Work email' },
        { name: 'phone', field_type: 'string', required: false, description: 'Phone number' },
        { name: 'title', field_type: 'string', required: false, description: 'Job title' },
        { name: 'department', field_type: 'string', required: false, description: 'Department' },
        { name: 'manager', field_type: 'string', required: false, description: 'Manager name' },
        { name: 'start_date', field_type: 'date', required: false, description: 'Start date' }
      ]
    end

    def event_management_fields
      [
        { name: 'event_name', field_type: 'string', required: true, description: 'Event name' },
        { name: 'description', field_type: 'text', required: false, description: 'Event description' },
        { name: 'event_date', field_type: 'datetime', required: true, description: 'Event date and time' },
        { name: 'end_date', field_type: 'datetime', required: false, description: 'End date and time' },
        { name: 'location', field_type: 'string', required: false, description: 'Venue/Location' },
        { name: 'capacity', field_type: 'integer', required: false, description: 'Maximum attendees' },
        { name: 'status', field_type: 'string', required: true, description: 'Event status', options: %w[draft published cancelled completed] }
      ]
    end

    def subscription_billing_fields
      [
        { name: 'plan_name', field_type: 'string', required: true, description: 'Subscription plan name' },
        { name: 'price', field_type: 'decimal', required: true, description: 'Monthly/Annual price' },
        { name: 'billing_cycle', field_type: 'string', required: true, description: 'Billing frequency', options: %w[monthly annual] },
        { name: 'status', field_type: 'string', required: true, description: 'Subscription status', options: %w[active paused cancelled expired] },
        { name: 'start_date', field_type: 'date', required: true, description: 'Subscription start' },
        { name: 'next_billing_date', field_type: 'date', required: false, description: 'Next billing date' },
        { name: 'customer_email', field_type: 'string', required: true, description: 'Customer email' }
      ]
    end

    def knowledge_base_fields
      [
        { name: 'title', field_type: 'string', required: true, description: 'Article title' },
        { name: 'content', field_type: 'text', required: true, description: 'Article content' },
        { name: 'category', field_type: 'string', required: false, description: 'Article category' },
        { name: 'tags', field_type: 'json', required: false, description: 'Article tags' },
        { name: 'status', field_type: 'string', required: true, description: 'Publication status', options: %w[draft published archived] },
        { name: 'view_count', field_type: 'integer', required: false, description: 'Number of views' },
        { name: 'author', field_type: 'string', required: false, description: 'Article author' }
      ]
    end

    # Method to get template with fields for customization
    public def get_template_for_customization(template_key)
      template = TEMPLATES[template_key]
      return nil unless template

      {
        name: template[:name],
        description: template[:description],
        icon: template[:icon],
        features: template[:features],
        fields: default_fields_for(template_key),
        original_template: template_key
      }
    end

    def request_build(template_key, template)
      tool = Tools::RequestModuleTool.new(
        user: @user,
        entity: @entity,
        context: { template_install: true }
      )

      result = tool.execute(
        module_name: template[:name],
        requirements: template[:requirements],
        features: template[:features],
        integrations: [],
        ui_modes: %w[simple advanced]
      )

      {
        module_slug: result[:module_slug],
        execution_id: result[:execution_id]
      }
    end
  end
end

