# frozen_string_literal: true

# Modules::ArchetypeIntelligence
#
# Smart detection of module requirements based on name/description.
# When someone says "Social Media Manager", this knows what integrations,
# automations, and workflows are typically needed.
#
# Used by Platform Factory to proactively suggest complete solutions.
#
module Modules
  class ArchetypeIntelligence
    ARCHETYPES = {
      # ========================================
      # SOCIAL MEDIA / CONTENT
      # ========================================
      social_media: {
        triggers: %w[social media instagram facebook twitter tiktok linkedin content post schedule],
        name: 'Social Media Management',
        description: 'Content planning, scheduling, and analytics across platforms',
        canvas_views: %w[list form detail dashboard],
        suggested_integrations: [
          { name: 'instagram', type: 'oauth', description: 'Connect to Instagram for posting and analytics' },
          { name: 'facebook', type: 'oauth', description: 'Connect to Facebook Pages for posting and analytics' },
          { name: 'twitter', type: 'oauth', description: 'Connect to Twitter/X for posting and analytics' },
          { name: 'linkedin', type: 'oauth', description: 'Connect to LinkedIn for professional content' },
          { name: 'buffer', type: 'api_key', description: 'Use Buffer for cross-platform scheduling' },
          { name: 'canva', type: 'oauth', description: 'Create graphics with Canva integration' }
        ],
        suggested_workflows: [
          { 
            name: 'Content Approval Flow',
            trigger: 'status_change',
            from_status: 'drafted',
            to_status: 'pending_approval',
            actions: ['notify_approver', 'set_due_date']
          },
          { 
            name: 'Auto-Publish Scheduled Posts',
            trigger: 'scheduled_datetime',
            field: 'scheduled_at',
            actions: ['publish_to_platform', 'update_status_to_published']
          },
          {
            name: 'Post-Publish Analytics',
            trigger: 'status_change',
            from_status: 'scheduled',
            to_status: 'published',
            delay: '24_hours',
            actions: ['fetch_engagement_metrics']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Daily Engagement Sync',
            schedule: 'daily',
            time: '09:00',
            action: 'fetch_all_platform_metrics',
            description: 'Pull engagement data from all connected platforms'
          },
          {
            name: 'Weekly Performance Report',
            schedule: 'weekly',
            day: 'monday',
            time: '08:00',
            action: 'generate_performance_report',
            description: 'Generate and send weekly social performance summary'
          },
          {
            name: 'Content Gap Alert',
            schedule: 'daily',
            time: '14:00',
            action: 'check_content_calendar',
            description: 'Alert if no content scheduled for next 3 days'
          }
        ],
        suggested_hub_hooks: [
          { event: 'post_published', action: 'notify_team', message: 'New post published: {{post.title}}' },
          { event: 'high_engagement', threshold: 'above_average', action: 'celebrate', message: '🎉 {{post.title}} is performing great!' },
          { event: 'post_needs_approval', action: 'request_review', mention: 'content_approvers' }
        ],
        core_fields: [
          { name: 'title', type: 'string', required: true },
          { name: 'content', type: 'text', ui_component: 'rich_text_editor' },
          { name: 'platform', type: 'select', options: %w[instagram facebook twitter linkedin tiktok] },
          { name: 'content_type', type: 'select', options: %w[image video carousel reel story text] },
          { name: 'status', type: 'select', options: %w[idea drafted pending_approval scheduled published archived] },
          { name: 'scheduled_at', type: 'datetime' },
          { name: 'published_at', type: 'datetime' },
          { name: 'hashtags', type: 'text' },
          { name: 'content_pillar', type: 'select', options: %w[educational promotional behind_the_scenes engagement user_generated] },
          { name: 'likes', type: 'integer', default: 0 },
          { name: 'comments', type: 'integer', default: 0 },
          { name: 'shares', type: 'integer', default: 0 },
          { name: 'reach', type: 'integer', default: 0 }
        ],
        sub_models: [
          {
            name: 'ContentCalendar',
            slug: 'content_calendar',
            description: 'Weekly/monthly content calendar entries',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_field: 'post_id', parent_model: nil },
            fields: [
              { name: 'week_start', type: 'date', required: true },
              { name: 'theme', type: 'string' },
              { name: 'notes', type: 'text' },
              { name: 'target_post_count', type: 'integer', default: 5 },
              { name: 'status', type: 'select', options: %w[planning active completed] }
            ]
          },
          {
            name: 'MediaAsset',
            slug: 'media_asset',
            description: 'Images, videos, and graphics for posts',
            canvas_views: %w[list form],
            relationship: { type: 'belongs_to', parent_field: 'post_id' },
            fields: [
              { name: 'title', type: 'string', required: true },
              { name: 'asset_type', type: 'select', options: %w[image video graphic template] },
              { name: 'url', type: 'string' },
              { name: 'alt_text', type: 'string' },
              { name: 'dimensions', type: 'string' },
              { name: 'file_size', type: 'integer' }
            ]
          }
        ]
      },

      # ========================================
      # CRM / SALES
      # ========================================
      crm: {
        triggers: %w[crm sales leads pipeline deals opportunities customers contacts],
        name: 'CRM / Sales Pipeline',
        description: 'Track leads, deals, and customer relationships',
        canvas_views: %w[list kanban form detail dashboard],
        native_capabilities: {
          note: 'AMOS has built-in CRM capabilities that can be used directly without building a custom app:',
          models: [
            {
              name: 'Opportunity',
              description: 'Sales deals with stage tracking (lead → qualified → proposal → negotiation → closed)',
              key_features: ['Pipeline stages with probabilities', 'Value and expected close date', 'Linked to contacts', 'Activity timeline']
            },
            {
              name: 'Activity',
              description: 'CRM activities linked to contacts and opportunities',
              types: %w[note email call meeting task form_submission ai_action stage_change]
            },
            {
              name: 'Contact',
              description: 'Customers and leads with engagement tracking',
              key_features: ['Lead scoring', 'Lifecycle stages', 'Email engagement history', 'Custom fields']
            }
          ],
          canvases: ['pipeline_viewer (Kanban sales pipeline)', 'contact_viewer (Contact list)', 'activities_viewer (Activity timeline)'],
          automation_hooks: [
            'Opportunities can trigger workflows on stage changes',
            'Activities auto-log from email sends, form submissions, calls',
            'Stale deal detection for follow-up reminders',
            'Lead scoring updates from engagement'
          ]
        },
        suggested_integrations: [
          { name: 'hubspot', type: 'oauth', description: 'Sync with HubSpot CRM' },
          { name: 'salesforce', type: 'oauth', description: 'Sync with Salesforce' },
          { name: 'email', type: 'smtp', description: 'Send emails to leads and customers' },
          { name: 'calendar', type: 'oauth', description: 'Schedule meetings with leads' },
          { name: 'linkedin_sales', type: 'oauth', description: 'LinkedIn Sales Navigator integration' }
        ],
        suggested_workflows: [
          {
            name: 'Lead Qualification',
            trigger: 'record_created',
            actions: ['score_lead', 'assign_to_rep', 'notify_owner']
          },
          {
            name: 'Deal Stage Progression',
            trigger: 'status_change',
            actions: ['update_probability', 'notify_team', 'create_follow_up_task']
          },
          {
            name: 'Stale Deal Alert',
            trigger: 'no_activity',
            days: 7,
            actions: ['notify_owner', 'suggest_follow_up']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Daily Pipeline Review',
            schedule: 'daily',
            time: '08:00',
            action: 'generate_pipeline_summary',
            description: 'Morning pipeline health check'
          },
          {
            name: 'Weekly Forecast',
            schedule: 'weekly',
            day: 'friday',
            time: '16:00',
            action: 'generate_forecast_report',
            description: 'Weekly sales forecast for leadership'
          }
        ],
        suggested_hub_hooks: [
          { event: 'deal_won', action: 'celebrate', message: '🎉 Deal closed: {{deal.name}} for {{deal.value}}!' },
          { event: 'deal_stage_changed', action: 'notify_team' },
          { event: 'lead_assigned', action: 'dm_owner', message: 'New lead assigned to you: {{lead.name}}' }
        ]
      },

      # ========================================
      # INVENTORY / E-COMMERCE
      # ========================================
      inventory: {
        triggers: %w[inventory stock products warehouse ecommerce supply chain sku],
        name: 'Inventory Management',
        description: 'Track products, stock levels, and suppliers',
        canvas_views: %w[list form detail dashboard],
        suggested_integrations: [
          { name: 'shopify', type: 'oauth', description: 'Sync with Shopify store' },
          { name: 'woocommerce', type: 'api_key', description: 'Sync with WooCommerce' },
          { name: 'stripe', type: 'oauth', description: 'Payment processing' },
          { name: 'shipstation', type: 'api_key', description: 'Shipping and fulfillment' },
          { name: 'quickbooks', type: 'oauth', description: 'Accounting sync' }
        ],
        suggested_workflows: [
          {
            name: 'Low Stock Alert',
            trigger: 'field_below_threshold',
            field: 'quantity',
            threshold: 'reorder_point',
            actions: ['notify_purchaser', 'create_reorder_request']
          },
          {
            name: 'New Order Processing',
            trigger: 'webhook',
            source: 'shopify_order_created',
            actions: ['update_stock', 'create_fulfillment_task']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Daily Stock Sync',
            schedule: 'daily',
            time: '06:00',
            action: 'sync_all_channels',
            description: 'Sync stock levels across all sales channels'
          },
          {
            name: 'Weekly Inventory Report',
            schedule: 'weekly',
            day: 'monday',
            time: '09:00',
            action: 'generate_inventory_report',
            description: 'Weekly inventory status and reorder recommendations'
          }
        ],
        suggested_hub_hooks: [
          { event: 'low_stock', action: 'alert_urgent', message: '⚠️ Low stock alert: {{product.name}} ({{product.quantity}} left)' },
          { event: 'reorder_completed', action: 'notify_team', message: 'Reorder placed for {{product.name}}' }
        ],
        core_fields: [
          { name: 'name', type: 'string', required: true },
          { name: 'sku', type: 'string', required: true },
          { name: 'description', type: 'text' },
          { name: 'price', type: 'decimal' },
          { name: 'cost', type: 'decimal' },
          { name: 'quantity', type: 'integer', default: 0 },
          { name: 'reorder_point', type: 'integer', default: 10 },
          { name: 'reorder_quantity', type: 'integer', default: 50 },
          { name: 'status', type: 'select', options: %w[active discontinued out_of_stock backordered] },
          { name: 'location', type: 'string' },
          { name: 'barcode', type: 'string' },
          { name: 'weight', type: 'decimal' }
        ],
        sub_models: [
          {
            name: 'Category',
            slug: 'category',
            description: 'Product categories for organization',
            canvas_views: %w[list form],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'description', type: 'text' },
              { name: 'parent_id', type: 'integer' }
            ]
          },
          {
            name: 'Supplier',
            slug: 'supplier',
            description: 'Product suppliers and vendors',
            canvas_views: %w[list form detail],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'contact_name', type: 'string' },
              { name: 'email', type: 'string' },
              { name: 'phone', type: 'string' },
              { name: 'address', type: 'text' },
              { name: 'lead_time_days', type: 'integer', default: 7 },
              { name: 'status', type: 'select', options: %w[active inactive preferred] }
            ]
          },
          {
            name: 'StockMovement',
            slug: 'stock_movement',
            description: 'Track stock ins, outs, and adjustments',
            canvas_views: %w[list form],
            relationship: { type: 'belongs_to', parent_field: 'product_id' },
            fields: [
              { name: 'movement_type', type: 'select', options: %w[in out adjustment transfer], required: true },
              { name: 'quantity', type: 'integer', required: true },
              { name: 'reference', type: 'string' },
              { name: 'notes', type: 'text' },
              { name: 'moved_at', type: 'datetime' }
            ]
          },
          {
            name: 'PurchaseOrder',
            slug: 'purchase_order',
            description: 'Orders placed with suppliers',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_field: 'supplier_id', parent_model: 'Supplier' },
            fields: [
              { name: 'order_number', type: 'string', required: true },
              { name: 'status', type: 'select', options: %w[draft submitted confirmed shipped received cancelled] },
              { name: 'total_amount', type: 'decimal' },
              { name: 'expected_date', type: 'date' },
              { name: 'received_date', type: 'date' },
              { name: 'notes', type: 'text' }
            ]
          }
        ]
      },

      # ========================================
      # PROJECT MANAGEMENT
      # ========================================
      project: {
        triggers: %w[project task milestone sprint kanban agile workflow team],
        name: 'Project Management',
        description: 'Track projects, tasks, and team progress',
        canvas_views: %w[list kanban form detail dashboard],
        suggested_integrations: [
          { name: 'github', type: 'oauth', description: 'Link to code repositories' },
          { name: 'gitlab', type: 'oauth', description: 'Link to GitLab repos' },
          { name: 'slack', type: 'oauth', description: 'Team notifications' },
          { name: 'calendar', type: 'oauth', description: 'Sync deadlines to calendar' }
        ],
        suggested_workflows: [
          {
            name: 'Task Assignment',
            trigger: 'field_changed',
            field: 'assignee',
            actions: ['notify_assignee', 'add_to_workload']
          },
          {
            name: 'Sprint Completion',
            trigger: 'all_tasks_completed',
            actions: ['close_sprint', 'generate_retrospective', 'notify_team']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Daily Standup Summary',
            schedule: 'daily',
            time: '09:00',
            action: 'generate_standup_summary',
            description: 'AI-generated standup from task updates'
          },
          {
            name: 'Sprint Review Prep',
            schedule: 'weekly',
            day: 'friday',
            time: '14:00',
            action: 'generate_sprint_review',
            description: 'Prepare sprint review materials'
          }
        ],
        suggested_hub_hooks: [
          { event: 'task_completed', action: 'notify_project', message: '✅ {{task.name}} completed by {{task.assignee}}' },
          { event: 'deadline_approaching', days: 2, action: 'remind_assignee' },
          { event: 'project_milestone', action: 'celebrate', message: '🎯 Milestone reached: {{milestone.name}}!' }
        ],
        core_fields: [
          { name: 'name', type: 'string', required: true },
          { name: 'description', type: 'text' },
          { name: 'status', type: 'select', options: %w[planning active on_hold completed archived] },
          { name: 'priority', type: 'select', options: %w[low medium high urgent] },
          { name: 'start_date', type: 'date' },
          { name: 'due_date', type: 'date' },
          { name: 'progress', type: 'integer', default: 0 },
          { name: 'owner', type: 'string' },
          { name: 'budget', type: 'decimal' }
        ],
        sub_models: [
          {
            name: 'Task',
            slug: 'task',
            description: 'Individual tasks within a project',
            canvas_views: %w[list kanban form detail],
            relationship: { type: 'belongs_to', parent_field: 'project_id' },
            fields: [
              { name: 'title', type: 'string', required: true },
              { name: 'description', type: 'text' },
              { name: 'status', type: 'select', options: %w[todo in_progress review done blocked] },
              { name: 'priority', type: 'select', options: %w[low medium high urgent] },
              { name: 'assignee', type: 'string' },
              { name: 'due_date', type: 'date' },
              { name: 'estimated_hours', type: 'decimal' },
              { name: 'actual_hours', type: 'decimal' },
              { name: 'labels', type: 'string' },
              { name: 'sort_order', type: 'integer', default: 0 }
            ]
          },
          {
            name: 'Milestone',
            slug: 'milestone',
            description: 'Project milestones and key deadlines',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_field: 'project_id' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'description', type: 'text' },
              { name: 'target_date', type: 'date', required: true },
              { name: 'status', type: 'select', options: %w[upcoming in_progress completed missed] },
              { name: 'deliverables', type: 'text' }
            ]
          },
          {
            name: 'TimeEntry',
            slug: 'time_entry',
            description: 'Time tracking entries for tasks',
            canvas_views: %w[list form],
            relationship: { type: 'belongs_to', parent_field: 'task_id', parent_model: 'Task' },
            fields: [
              { name: 'hours', type: 'decimal', required: true },
              { name: 'description', type: 'text' },
              { name: 'date', type: 'date', required: true },
              { name: 'user_name', type: 'string' },
              { name: 'billable', type: 'boolean', default: true }
            ]
          }
        ]
      },

      # ========================================
      # KNOWLEDGE BASE / HELP CENTER
      # ========================================
      knowledge_base: {
        triggers: %w[knowledge base articles docs documentation faq help center wiki],
        name: 'Knowledge Base',
        description: 'Create and manage documentation and help articles',
        suggested_integrations: [
          { name: 'intercom', type: 'oauth', description: 'Embed in Intercom chat' },
          { name: 'zendesk', type: 'oauth', description: 'Link to Zendesk tickets' },
          { name: 'algolia', type: 'api_key', description: 'Enhanced search' }
        ],
        suggested_workflows: [
          {
            name: 'Article Review',
            trigger: 'status_change',
            from_status: 'draft',
            to_status: 'review',
            actions: ['notify_reviewers', 'set_review_deadline']
          },
          {
            name: 'Low Rating Alert',
            trigger: 'field_below_threshold',
            field: 'helpful_rating',
            threshold: 50,
            actions: ['flag_for_improvement', 'notify_author']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Stale Content Review',
            schedule: 'monthly',
            day: 1,
            time: '10:00',
            action: 'identify_stale_articles',
            description: 'Find articles not updated in 90+ days'
          },
          {
            name: 'Weekly Usage Report',
            schedule: 'weekly',
            day: 'monday',
            time: '09:00',
            action: 'generate_usage_report',
            description: 'Most viewed articles and search trends'
          }
        ],
        suggested_hub_hooks: [
          { event: 'article_published', action: 'notify_team', message: '📄 New article: {{article.title}}' },
          { event: 'article_highly_rated', action: 'celebrate', message: '⭐ {{article.title}} is helping lots of people!' }
        ],
        special_features: ['public_portal', 'search_embedding', 'version_history'],
        core_fields: [
          { name: 'title', type: 'string', required: true },
          { name: 'content', type: 'text', ui_component: 'rich_text_editor' },
          { name: 'status', type: 'select', options: %w[draft review published archived] },
          { name: 'category', type: 'string' },
          { name: 'author', type: 'string' },
          { name: 'helpful_rating', type: 'integer', default: 0 },
          { name: 'view_count', type: 'integer', default: 0 },
          { name: 'published_at', type: 'datetime' },
          { name: 'last_reviewed_at', type: 'datetime' }
        ],
        canvas_views: %w[list form detail],
        sub_models: [
          {
            name: 'Category',
            slug: 'kb_category',
            description: 'Organize articles into categories',
            canvas_views: %w[list form],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'description', type: 'text' },
              { name: 'icon', type: 'string' },
              { name: 'sort_order', type: 'integer', default: 0 },
              { name: 'parent_id', type: 'integer' }
            ]
          },
          {
            name: 'ArticleFeedback',
            slug: 'article_feedback',
            description: 'Reader feedback on articles',
            canvas_views: %w[list],
            relationship: { type: 'belongs_to', parent_field: 'article_id' },
            fields: [
              { name: 'helpful', type: 'boolean', required: true },
              { name: 'comment', type: 'text' },
              { name: 'reader_email', type: 'string' }
            ]
          }
        ]
      },

      # ========================================
      # EVENTS / CALENDAR
      # ========================================
      events: {
        triggers: %w[event calendar conference meeting webinar rsvp registration attendee],
        name: 'Event Management',
        description: 'Plan and manage events, registrations, and attendees',
        suggested_integrations: [
          { name: 'google_calendar', type: 'oauth', description: 'Sync to Google Calendar' },
          { name: 'zoom', type: 'oauth', description: 'Auto-create Zoom meetings' },
          { name: 'eventbrite', type: 'oauth', description: 'Ticket sales and registration' },
          { name: 'mailchimp', type: 'oauth', description: 'Event email campaigns' }
        ],
        suggested_workflows: [
          {
            name: 'Registration Confirmation',
            trigger: 'record_created',
            model: 'registration',
            actions: ['send_confirmation_email', 'add_to_calendar', 'update_capacity']
          },
          {
            name: 'Event Reminder',
            trigger: 'scheduled_datetime',
            field: 'event_date',
            offset: '-1_day',
            actions: ['send_reminder_email', 'notify_attendees']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Pre-Event Checklist',
            schedule: 'triggered',
            trigger: '1_week_before_event',
            action: 'generate_checklist',
            description: 'Generate pre-event preparation checklist'
          },
          {
            name: 'Post-Event Survey',
            schedule: 'triggered',
            trigger: '1_day_after_event',
            action: 'send_survey',
            description: 'Send feedback survey to attendees'
          }
        ],
        suggested_hub_hooks: [
          { event: 'new_registration', action: 'notify_team', message: '🎟️ New registration for {{event.name}}: {{attendee.name}}' },
          { event: 'capacity_reached', action: 'alert_urgent', message: '⚠️ {{event.name}} is now at capacity!' }
        ],
        core_fields: [
          { name: 'name', type: 'string', required: true },
          { name: 'description', type: 'text' },
          { name: 'event_type', type: 'select', options: %w[conference workshop webinar meetup social training] },
          { name: 'status', type: 'select', options: %w[planning open closed completed cancelled] },
          { name: 'event_date', type: 'datetime', required: true },
          { name: 'end_date', type: 'datetime' },
          { name: 'location', type: 'string' },
          { name: 'capacity', type: 'integer' },
          { name: 'price', type: 'decimal' },
          { name: 'organizer', type: 'string' }
        ],
        canvas_views: %w[list form detail dashboard],
        sub_models: [
          {
            name: 'Registration',
            slug: 'registration',
            description: 'Event registrations and attendees',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_field: 'event_id' },
            fields: [
              { name: 'attendee_name', type: 'string', required: true },
              { name: 'attendee_email', type: 'string', required: true },
              { name: 'ticket_type', type: 'select', options: %w[general vip speaker sponsor] },
              { name: 'status', type: 'select', options: %w[pending confirmed checked_in cancelled refunded] },
              { name: 'amount_paid', type: 'decimal' },
              { name: 'notes', type: 'text' }
            ]
          },
          {
            name: 'Session',
            slug: 'session',
            description: 'Individual sessions within an event',
            canvas_views: %w[list form],
            relationship: { type: 'belongs_to', parent_field: 'event_id' },
            fields: [
              { name: 'title', type: 'string', required: true },
              { name: 'speaker', type: 'string' },
              { name: 'start_time', type: 'datetime', required: true },
              { name: 'end_time', type: 'datetime' },
              { name: 'room', type: 'string' },
              { name: 'description', type: 'text' },
              { name: 'capacity', type: 'integer' }
            ]
          }
        ]
      },

      # ========================================
      # FINANCE / BILLING
      # ========================================
      finance: {
        triggers: %w[invoice expense budget finance billing payment accounting],
        name: 'Financial Tracking',
        description: 'Track income, expenses, invoices, and budgets',
        suggested_integrations: [
          { name: 'quickbooks', type: 'oauth', description: 'Sync with QuickBooks' },
          { name: 'xero', type: 'oauth', description: 'Sync with Xero' },
          { name: 'stripe', type: 'oauth', description: 'Payment processing' },
          { name: 'plaid', type: 'oauth', description: 'Bank account connection' }
        ],
        suggested_workflows: [
          {
            name: 'Invoice Payment Received',
            trigger: 'webhook',
            source: 'stripe_payment_succeeded',
            actions: ['mark_invoice_paid', 'send_receipt', 'update_books']
          },
          {
            name: 'Expense Approval',
            trigger: 'record_created',
            model: 'expense',
            condition: 'amount > 500',
            actions: ['request_manager_approval', 'hold_reimbursement']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Monthly Close',
            schedule: 'monthly',
            day: 'last',
            time: '18:00',
            action: 'generate_monthly_close',
            description: 'Prepare monthly financial close'
          },
          {
            name: 'Invoice Reminders',
            schedule: 'weekly',
            day: 'tuesday',
            time: '10:00',
            action: 'send_overdue_reminders',
            description: 'Send payment reminders for overdue invoices'
          }
        ],
        suggested_hub_hooks: [
          { event: 'large_payment_received', threshold: 10000, action: 'celebrate', message: '💰 Large payment received: {{payment.amount}}!' },
          { event: 'invoice_overdue', action: 'alert_urgent', message: '⚠️ Invoice #{{invoice.number}} is overdue' }
        ],
        core_fields: [
          { name: 'description', type: 'string', required: true },
          { name: 'category', type: 'select', options: %w[income expense reimbursement transfer] },
          { name: 'amount', type: 'decimal', required: true },
          { name: 'date', type: 'date', required: true },
          { name: 'payment_method', type: 'select', options: %w[cash credit_card bank_transfer check paypal other] },
          { name: 'status', type: 'select', options: %w[pending approved rejected paid] },
          { name: 'reference', type: 'string' },
          { name: 'notes', type: 'text' }
        ],
        canvas_views: %w[list form detail dashboard],
        sub_models: [
          {
            name: 'Invoice',
            slug: 'invoice',
            description: 'Customer invoices for billing',
            canvas_views: %w[list form detail],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'invoice_number', type: 'string', required: true },
              { name: 'client_name', type: 'string', required: true },
              { name: 'client_email', type: 'string' },
              { name: 'amount', type: 'decimal', required: true },
              { name: 'tax_amount', type: 'decimal', default: 0 },
              { name: 'status', type: 'select', options: %w[draft sent viewed paid overdue cancelled] },
              { name: 'issue_date', type: 'date', required: true },
              { name: 'due_date', type: 'date', required: true },
              { name: 'paid_date', type: 'date' },
              { name: 'notes', type: 'text' }
            ]
          },
          {
            name: 'BudgetCategory',
            slug: 'budget_category',
            description: 'Budget categories with spending limits',
            canvas_views: %w[list form],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'monthly_budget', type: 'decimal', required: true },
              { name: 'spent_this_month', type: 'decimal', default: 0 },
              { name: 'fiscal_year', type: 'string' }
            ]
          }
        ]
      },

      # ========================================
      # HR / PEOPLE MANAGEMENT
      # ========================================
      hr: {
        triggers: %w[hr human resources employee onboarding hiring recruitment people staff team pto],
        name: 'HR / People Management',
        description: 'Manage employees, onboarding, time off, and recruitment',
        canvas_views: %w[list form detail dashboard],
        suggested_integrations: [
          { name: 'slack', type: 'oauth', description: 'Team communication and notifications' },
          { name: 'google_calendar', type: 'oauth', description: 'Sync schedules and time off' },
          { name: 'docusign', type: 'oauth', description: 'Digital document signing' },
          { name: 'indeed', type: 'api_key', description: 'Job posting and candidate sourcing' }
        ],
        suggested_workflows: [
          {
            name: 'New Hire Onboarding',
            trigger: 'record_created',
            model: 'employee',
            actions: ['create_onboarding_checklist', 'notify_manager', 'send_welcome_email', 'provision_accounts']
          },
          {
            name: 'PTO Approval',
            trigger: 'record_created',
            model: 'time_off_request',
            actions: ['notify_manager', 'check_conflicts', 'update_calendar']
          },
          {
            name: 'Performance Review Cycle',
            trigger: 'scheduled_datetime',
            actions: ['create_review_forms', 'notify_managers', 'set_deadlines']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Birthday Reminders',
            schedule: 'daily',
            time: '08:00',
            action: 'check_upcoming_birthdays',
            description: 'Notify team of upcoming birthdays'
          },
          {
            name: 'Monthly Headcount Report',
            schedule: 'monthly',
            day: 1,
            time: '09:00',
            action: 'generate_headcount_report',
            description: 'Monthly headcount and turnover report'
          }
        ],
        suggested_hub_hooks: [
          { event: 'new_hire', action: 'notify_team', message: 'Welcome {{employee.name}} to the team!' },
          { event: 'work_anniversary', action: 'celebrate', message: '{{employee.name}} celebrates {{years}} years!' }
        ],
        core_fields: [
          { name: 'first_name', type: 'string', required: true },
          { name: 'last_name', type: 'string', required: true },
          { name: 'email', type: 'string', required: true },
          { name: 'phone', type: 'string' },
          { name: 'department', type: 'select', options: %w[engineering marketing sales support hr finance operations] },
          { name: 'title', type: 'string' },
          { name: 'hire_date', type: 'date', required: true },
          { name: 'status', type: 'select', options: %w[active onboarding on_leave terminated] },
          { name: 'manager', type: 'string' },
          { name: 'salary', type: 'decimal' },
          { name: 'location', type: 'string' }
        ],
        sub_models: [
          {
            name: 'TimeOffRequest',
            slug: 'time_off_request',
            description: 'PTO and time off requests',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_field: 'employee_id' },
            fields: [
              { name: 'request_type', type: 'select', options: %w[vacation sick personal bereavement jury_duty], required: true },
              { name: 'start_date', type: 'date', required: true },
              { name: 'end_date', type: 'date', required: true },
              { name: 'hours', type: 'decimal' },
              { name: 'status', type: 'select', options: %w[pending approved denied cancelled] },
              { name: 'notes', type: 'text' },
              { name: 'approved_by', type: 'string' }
            ]
          },
          {
            name: 'JobPosting',
            slug: 'job_posting',
            description: 'Open positions and recruitment',
            canvas_views: %w[list form detail],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'title', type: 'string', required: true },
              { name: 'department', type: 'string', required: true },
              { name: 'description', type: 'text' },
              { name: 'requirements', type: 'text' },
              { name: 'salary_range', type: 'string' },
              { name: 'location', type: 'string' },
              { name: 'status', type: 'select', options: %w[draft open interviewing filled closed] },
              { name: 'posted_date', type: 'date' },
              { name: 'hiring_manager', type: 'string' }
            ]
          },
          {
            name: 'Applicant',
            slug: 'applicant',
            description: 'Job applicants and candidates',
            canvas_views: %w[list kanban form detail],
            relationship: { type: 'belongs_to', parent_field: 'job_posting_id', parent_model: 'JobPosting' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'email', type: 'string', required: true },
              { name: 'phone', type: 'string' },
              { name: 'resume_url', type: 'string' },
              { name: 'stage', type: 'select', options: %w[applied screening phone_screen interview offer hired rejected] },
              { name: 'rating', type: 'integer' },
              { name: 'notes', type: 'text' },
              { name: 'applied_date', type: 'date' }
            ]
          }
        ]
      },

      # ========================================
      # REAL ESTATE
      # ========================================
      real_estate: {
        triggers: %w[real estate property listing rental lease tenant landlord mortgage realty],
        name: 'Real Estate Management',
        description: 'Manage properties, listings, tenants, and transactions',
        canvas_views: %w[list form detail dashboard],
        suggested_integrations: [
          { name: 'zillow', type: 'api_key', description: 'Pull property data from Zillow' },
          { name: 'google_maps', type: 'api_key', description: 'Property location and mapping' },
          { name: 'docusign', type: 'oauth', description: 'Lease and contract signing' },
          { name: 'stripe', type: 'oauth', description: 'Rent payment collection' }
        ],
        suggested_workflows: [
          {
            name: 'New Listing Published',
            trigger: 'status_change',
            from_status: 'draft',
            to_status: 'active',
            actions: ['publish_to_website', 'notify_agents', 'syndicate_listing']
          },
          {
            name: 'Lease Expiration Warning',
            trigger: 'scheduled_datetime',
            field: 'lease_end_date',
            offset: '-30_days',
            actions: ['notify_tenant', 'notify_landlord', 'create_renewal_task']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Rent Collection Reminders',
            schedule: 'monthly',
            day: 25,
            time: '09:00',
            action: 'send_rent_reminders',
            description: 'Remind tenants of upcoming rent due dates'
          },
          {
            name: 'Weekly Listing Report',
            schedule: 'weekly',
            day: 'monday',
            time: '09:00',
            action: 'generate_listing_report',
            description: 'Active listings performance and inquiries'
          }
        ],
        suggested_hub_hooks: [
          { event: 'property_sold', action: 'celebrate', message: 'Property sold: {{property.address}} for {{property.sale_price}}!' },
          { event: 'new_inquiry', action: 'notify_agent', message: 'New inquiry on {{listing.address}} from {{inquiry.name}}' }
        ],
        core_fields: [
          { name: 'address', type: 'string', required: true },
          { name: 'property_type', type: 'select', options: %w[residential commercial land industrial multi_family] },
          { name: 'listing_type', type: 'select', options: %w[sale rent lease] },
          { name: 'status', type: 'select', options: %w[draft active under_contract sold rented off_market] },
          { name: 'price', type: 'decimal', required: true },
          { name: 'bedrooms', type: 'integer' },
          { name: 'bathrooms', type: 'decimal' },
          { name: 'square_feet', type: 'integer' },
          { name: 'year_built', type: 'integer' },
          { name: 'description', type: 'text' },
          { name: 'agent', type: 'string' }
        ],
        sub_models: [
          {
            name: 'Tenant',
            slug: 'tenant',
            description: 'Tenants and lease information',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_field: 'property_id' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'email', type: 'string', required: true },
              { name: 'phone', type: 'string' },
              { name: 'lease_start_date', type: 'date', required: true },
              { name: 'lease_end_date', type: 'date', required: true },
              { name: 'monthly_rent', type: 'decimal', required: true },
              { name: 'deposit', type: 'decimal' },
              { name: 'status', type: 'select', options: %w[active pending_move_in notice_given moved_out evicted] }
            ]
          },
          {
            name: 'MaintenanceRequest',
            slug: 'maintenance_request',
            description: 'Property maintenance and repair requests',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_field: 'property_id' },
            fields: [
              { name: 'title', type: 'string', required: true },
              { name: 'description', type: 'text', required: true },
              { name: 'priority', type: 'select', options: %w[low medium high emergency] },
              { name: 'status', type: 'select', options: %w[submitted scheduled in_progress completed] },
              { name: 'requested_by', type: 'string' },
              { name: 'assigned_to', type: 'string' },
              { name: 'cost', type: 'decimal' },
              { name: 'completed_date', type: 'date' }
            ]
          },
          {
            name: 'Showing',
            slug: 'showing',
            description: 'Property showing appointments',
            canvas_views: %w[list form],
            relationship: { type: 'belongs_to', parent_field: 'property_id' },
            fields: [
              { name: 'prospect_name', type: 'string', required: true },
              { name: 'prospect_email', type: 'string' },
              { name: 'prospect_phone', type: 'string' },
              { name: 'showing_date', type: 'datetime', required: true },
              { name: 'status', type: 'select', options: %w[scheduled confirmed completed cancelled no_show] },
              { name: 'agent', type: 'string' },
              { name: 'feedback', type: 'text' }
            ]
          }
        ]
      },

      # ========================================
      # HELPDESK / SUPPORT
      # ========================================
      helpdesk: {
        triggers: %w[helpdesk support ticket help desk customer service issue bug request sla],
        name: 'Help Desk / Support',
        description: 'Customer support ticketing, SLA tracking, and knowledge management',
        canvas_views: %w[list kanban form detail dashboard],
        suggested_integrations: [
          { name: 'intercom', type: 'oauth', description: 'Live chat integration' },
          { name: 'zendesk', type: 'oauth', description: 'Sync with Zendesk' },
          { name: 'slack', type: 'oauth', description: 'Internal team notifications' },
          { name: 'email', type: 'smtp', description: 'Email ticket responses' }
        ],
        suggested_workflows: [
          {
            name: 'Ticket Auto-Assignment',
            trigger: 'record_created',
            model: 'ticket',
            actions: ['classify_priority', 'assign_to_agent', 'send_acknowledgment']
          },
          {
            name: 'SLA Escalation',
            trigger: 'sla_breach',
            actions: ['escalate_to_supervisor', 'notify_customer', 'update_priority']
          },
          {
            name: 'Resolution Feedback',
            trigger: 'status_change',
            from_status: 'resolved',
            to_status: 'closed',
            actions: ['send_satisfaction_survey']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Stale Ticket Alert',
            schedule: 'daily',
            time: '09:00',
            action: 'check_stale_tickets',
            description: 'Flag tickets with no response for 24+ hours'
          },
          {
            name: 'Weekly Support Metrics',
            schedule: 'weekly',
            day: 'monday',
            time: '08:00',
            action: 'generate_support_report',
            description: 'Response times, resolution rates, customer satisfaction'
          }
        ],
        suggested_hub_hooks: [
          { event: 'urgent_ticket', action: 'alert_urgent', message: 'Urgent ticket from {{ticket.requester}}: {{ticket.subject}}' },
          { event: 'sla_warning', action: 'notify_team', message: 'SLA breach approaching for ticket #{{ticket.id}}' }
        ],
        core_fields: [
          { name: 'subject', type: 'string', required: true },
          { name: 'description', type: 'text', required: true },
          { name: 'status', type: 'select', options: %w[new open pending resolved closed] },
          { name: 'priority', type: 'select', options: %w[low medium high urgent] },
          { name: 'category', type: 'select', options: %w[billing technical account feature_request general] },
          { name: 'requester_name', type: 'string' },
          { name: 'requester_email', type: 'string' },
          { name: 'assigned_to', type: 'string' },
          { name: 'resolution', type: 'text' },
          { name: 'resolved_at', type: 'datetime' }
        ],
        sub_models: [
          {
            name: 'TicketComment',
            slug: 'ticket_comment',
            description: 'Comments and replies on support tickets',
            canvas_views: %w[list form],
            relationship: { type: 'belongs_to', parent_field: 'ticket_id' },
            fields: [
              { name: 'body', type: 'text', required: true },
              { name: 'author', type: 'string', required: true },
              { name: 'is_internal', type: 'boolean', default: false },
              { name: 'is_from_customer', type: 'boolean', default: false }
            ]
          },
          {
            name: 'CannedResponse',
            slug: 'canned_response',
            description: 'Pre-written responses for common issues',
            canvas_views: %w[list form],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'title', type: 'string', required: true },
              { name: 'body', type: 'text', required: true },
              { name: 'category', type: 'string' },
              { name: 'usage_count', type: 'integer', default: 0 }
            ]
          }
        ]
      },

      # ========================================
      # EDUCATION / LMS
      # ========================================
      education: {
        triggers: %w[education course student lms learning enrollment grade assignment class classroom school training],
        name: 'Education / LMS',
        description: 'Learning management system for courses, students, and grades',
        canvas_views: %w[list form detail dashboard],
        suggested_integrations: [
          { name: 'zoom', type: 'oauth', description: 'Video conferencing for live classes' },
          { name: 'google_classroom', type: 'oauth', description: 'Sync with Google Classroom' }
        ],
        suggested_workflows: [
          {
            name: 'Auto-Enroll New Student',
            trigger: 'record_created',
            actions: ['send_welcome_email', 'assign_default_courses']
          },
          {
            name: 'Grade Submission Notification',
            trigger: 'status_change',
            from_status: 'submitted',
            to_status: 'graded',
            actions: ['notify_student']
          },
          {
            name: 'Course Completion Certificate',
            trigger: 'status_change',
            from_status: 'in_progress',
            to_status: 'completed',
            actions: ['generate_certificate', 'notify_student']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Daily Assignment Reminders',
            schedule: 'daily',
            time: '08:00',
            action: 'send_assignment_reminders',
            description: 'Remind students of upcoming assignment deadlines'
          },
          {
            name: 'Weekly Progress Report',
            schedule: 'weekly',
            day: 'friday',
            time: '16:00',
            action: 'generate_student_progress_reports',
            description: 'Generate weekly progress summary for instructors'
          }
        ],
        suggested_hub_hooks: [
          { event: 'course_started', action: 'notify_team', message: 'New course started: {{course.name}}' },
          { event: 'student_enrolled', action: 'celebrate', message: '🎓 New student enrolled: {{student.name}}' }
        ],
        core_fields: [
          { name: 'name', type: 'string', required: true },
          { name: 'description', type: 'text' },
          { name: 'instructor', type: 'string' },
          { name: 'category', type: 'string' },
          { name: 'status', type: 'select', options: %w[draft enrollment_open in_progress completed archived] },
          { name: 'start_date', type: 'date' },
          { name: 'end_date', type: 'date' },
          { name: 'max_students', type: 'integer' },
          { name: 'price', type: 'decimal' }
        ],
        sub_models: [
          {
            name: 'Student',
            slug: 'student',
            description: 'Students enrolled in courses',
            canvas_views: %w[list form detail],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'email', type: 'string', required: true },
              { name: 'phone', type: 'string' },
              { name: 'status', type: 'select', options: %w[active inactive graduated withdrawn] },
              { name: 'enrollment_date', type: 'date' }
            ]
          },
          {
            name: 'Enrollment',
            slug: 'enrollment',
            description: 'Student enrollment in a course',
            canvas_views: %w[list form],
            relationship: { type: 'belongs_to', parent_model: nil, parent_field: 'course_id' },
            fields: [
              { name: 'student_name', type: 'string', required: true },
              { name: 'status', type: 'select', options: %w[enrolled in_progress completed dropped] },
              { name: 'enrolled_at', type: 'datetime' },
              { name: 'progress', type: 'integer', default: 0 },
              { name: 'final_grade', type: 'string' }
            ]
          },
          {
            name: 'Assignment',
            slug: 'assignment',
            description: 'Course assignments and homework',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_model: nil, parent_field: 'course_id' },
            fields: [
              { name: 'title', type: 'string', required: true },
              { name: 'description', type: 'text' },
              { name: 'due_date', type: 'date', required: true },
              { name: 'max_points', type: 'integer' },
              { name: 'status', type: 'select', options: %w[draft published closed graded] },
              { name: 'assignment_type', type: 'select', options: %w[homework quiz exam project] }
            ]
          }
        ]
      },

      # ========================================
      # FLEET MANAGEMENT
      # ========================================
      fleet_management: {
        triggers: %w[fleet vehicle driver trip maintenance fuel car truck transport logistics dispatch],
        name: 'Fleet Management',
        description: 'Vehicle fleet management with drivers, trips, and maintenance tracking',
        canvas_views: %w[list form detail dashboard],
        suggested_integrations: [
          { name: 'google_maps', type: 'api_key', description: 'GPS tracking and route mapping' },
          { name: 'fuel_cards', type: 'api_key', description: 'Fuel card transaction sync' }
        ],
        suggested_workflows: [
          {
            name: 'Maintenance Due Alert',
            trigger: 'field_changed',
            field: 'next_maintenance_date',
            actions: ['notify_fleet_manager', 'create_maintenance_task']
          },
          {
            name: 'Trip Completion Log',
            trigger: 'status_change',
            from_status: 'in_progress',
            to_status: 'completed',
            actions: ['log_mileage', 'update_vehicle_odometer']
          },
          {
            name: 'Low Fuel Alert',
            trigger: 'field_changed',
            field: 'fuel_level',
            actions: ['notify_driver']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Daily Vehicle Inspection Reminder',
            schedule: 'daily',
            time: '06:00',
            action: 'send_inspection_reminders',
            description: 'Remind drivers to complete pre-trip inspections'
          },
          {
            name: 'Weekly Fleet Report',
            schedule: 'weekly',
            day: 'monday',
            time: '09:00',
            action: 'generate_fleet_report',
            description: 'Generate weekly fleet utilization and cost report'
          }
        ],
        suggested_hub_hooks: [
          { event: 'vehicle_maintenance_due', action: 'notify_team', message: '🔧 Maintenance due for {{vehicle.name}}' },
          { event: 'trip_completed', action: 'log', message: 'Trip completed: {{trip.origin}} → {{trip.destination}}' }
        ],
        core_fields: [
          { name: 'name', type: 'string', required: true },
          { name: 'vehicle_type', type: 'select', options: %w[car truck van bus motorcycle] },
          { name: 'make', type: 'string' },
          { name: 'model', type: 'string' },
          { name: 'year', type: 'integer' },
          { name: 'license_plate', type: 'string' },
          { name: 'vin', type: 'string' },
          { name: 'status', type: 'select', options: %w[available in_use maintenance out_of_service] },
          { name: 'current_mileage', type: 'integer' },
          { name: 'fuel_type', type: 'select', options: %w[gasoline diesel electric hybrid] }
        ],
        sub_models: [
          {
            name: 'Driver',
            slug: 'driver',
            description: 'Fleet drivers',
            canvas_views: %w[list form detail],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'phone', type: 'string' },
              { name: 'email', type: 'string' },
              { name: 'license_number', type: 'string', required: true },
              { name: 'license_expiry', type: 'date' },
              { name: 'status', type: 'select', options: %w[active inactive suspended] }
            ]
          },
          {
            name: 'Trip',
            slug: 'trip',
            description: 'Vehicle trips and routes',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_model: nil, parent_field: 'vehicle_id' },
            fields: [
              { name: 'driver_name', type: 'string' },
              { name: 'origin', type: 'string', required: true },
              { name: 'destination', type: 'string', required: true },
              { name: 'start_time', type: 'datetime' },
              { name: 'end_time', type: 'datetime' },
              { name: 'distance_km', type: 'decimal' },
              { name: 'fuel_used', type: 'decimal' },
              { name: 'status', type: 'select', options: %w[planned in_progress completed cancelled] },
              { name: 'notes', type: 'text' }
            ]
          },
          {
            name: 'Maintenance',
            slug: 'maintenance',
            description: 'Vehicle maintenance and service records',
            canvas_views: %w[list form detail],
            relationship: { type: 'belongs_to', parent_model: nil, parent_field: 'vehicle_id' },
            fields: [
              { name: 'service_type', type: 'select', options: %w[oil_change tire_rotation brake_service inspection repair other], required: true },
              { name: 'description', type: 'text' },
              { name: 'scheduled_date', type: 'date', required: true },
              { name: 'completed_date', type: 'date' },
              { name: 'cost', type: 'decimal' },
              { name: 'mileage_at_service', type: 'integer' },
              { name: 'status', type: 'select', options: %w[scheduled in_progress completed cancelled] },
              { name: 'vendor', type: 'string' }
            ]
          },
          {
            name: 'FuelLog',
            slug: 'fuel_log',
            description: 'Fuel purchase and consumption records',
            canvas_views: %w[list form],
            relationship: { type: 'belongs_to', parent_model: nil, parent_field: 'vehicle_id' },
            fields: [
              { name: 'date', type: 'date', required: true },
              { name: 'liters', type: 'decimal', required: true },
              { name: 'cost', type: 'decimal', required: true },
              { name: 'odometer', type: 'integer' },
              { name: 'station', type: 'string' },
              { name: 'fuel_type', type: 'select', options: %w[gasoline diesel electric] }
            ]
          }
        ]
      },

      # ========================================
      # RESTAURANT / FOOD SERVICE
      # ========================================
      restaurant: {
        triggers: %w[restaurant menu food order table reservation kitchen dining cafe bar recipe ingredient],
        name: 'Restaurant Management',
        description: 'Restaurant operations: menu, orders, tables, reservations, and inventory',
        canvas_views: %w[list form detail dashboard kanban],
        suggested_integrations: [
          { name: 'doordash', type: 'api_key', description: 'DoorDash delivery integration' },
          { name: 'square', type: 'oauth', description: 'Square POS system integration' },
          { name: 'uber_eats', type: 'api_key', description: 'Uber Eats delivery integration' }
        ],
        suggested_workflows: [
          {
            name: 'New Order Alert',
            trigger: 'record_created',
            actions: ['notify_kitchen', 'update_table_status']
          },
          {
            name: 'Order Ready Notification',
            trigger: 'status_change',
            from_status: 'preparing',
            to_status: 'ready',
            actions: ['notify_server']
          },
          {
            name: 'Low Inventory Alert',
            trigger: 'field_changed',
            field: 'quantity',
            actions: ['notify_manager', 'create_purchase_order']
          }
        ],
        suggested_scheduled_tasks: [
          {
            name: 'Daily Inventory Check',
            schedule: 'daily',
            time: '06:00',
            action: 'generate_inventory_report',
            description: 'Check stock levels and flag items below reorder point'
          },
          {
            name: 'Weekly Sales Report',
            schedule: 'weekly',
            day: 'monday',
            time: '09:00',
            action: 'generate_sales_report',
            description: 'Generate weekly sales and revenue summary'
          },
          {
            name: 'Daily Reservation Summary',
            schedule: 'daily',
            time: '10:00',
            action: 'send_reservation_summary',
            description: 'Send the day\'s reservation list to front of house'
          }
        ],
        suggested_hub_hooks: [
          { event: 'reservation_created', action: 'notify_team', message: 'New reservation: {{reservation.name}} for {{reservation.party_size}} at {{reservation.time}}' },
          { event: 'high_volume_alert', action: 'notify_team', message: '🔥 Kitchen is busy — {{active_orders}} active orders' }
        ],
        core_fields: [
          { name: 'name', type: 'string', required: true },
          { name: 'description', type: 'text' },
          { name: 'category', type: 'select', options: %w[appetizer main_course dessert beverage side special] },
          { name: 'price', type: 'decimal', required: true },
          { name: 'status', type: 'select', options: %w[available unavailable seasonal coming_soon] },
          { name: 'is_featured', type: 'boolean' },
          { name: 'allergens', type: 'string' },
          { name: 'prep_time_minutes', type: 'integer' }
        ],
        sub_models: [
          {
            name: 'Order',
            slug: 'order',
            description: 'Customer orders',
            canvas_views: %w[list kanban detail],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'order_number', type: 'string', required: true },
              { name: 'table_number', type: 'string' },
              { name: 'customer_name', type: 'string' },
              { name: 'status', type: 'select', options: %w[pending preparing ready served completed cancelled] },
              { name: 'order_type', type: 'select', options: %w[dine_in takeout delivery] },
              { name: 'total', type: 'decimal' },
              { name: 'notes', type: 'text' },
              { name: 'ordered_at', type: 'datetime' }
            ]
          },
          {
            name: 'Table',
            slug: 'table',
            description: 'Restaurant tables',
            canvas_views: %w[list form],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'number', type: 'string', required: true },
              { name: 'capacity', type: 'integer', required: true },
              { name: 'section', type: 'select', options: %w[indoor outdoor patio bar private] },
              { name: 'status', type: 'select', options: %w[available occupied reserved cleaning] }
            ]
          },
          {
            name: 'Reservation',
            slug: 'reservation',
            description: 'Table reservations',
            canvas_views: %w[list form calendar],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'phone', type: 'string' },
              { name: 'email', type: 'string' },
              { name: 'party_size', type: 'integer', required: true },
              { name: 'reservation_date', type: 'date', required: true },
              { name: 'reservation_time', type: 'string', required: true },
              { name: 'status', type: 'select', options: %w[confirmed pending cancelled no_show completed] },
              { name: 'special_requests', type: 'text' }
            ]
          },
          {
            name: 'Ingredient',
            slug: 'ingredient',
            description: 'Kitchen inventory ingredients',
            canvas_views: %w[list form],
            relationship: { type: 'standalone' },
            fields: [
              { name: 'name', type: 'string', required: true },
              { name: 'category', type: 'select', options: %w[produce meat seafood dairy bakery beverage dry_goods spice other] },
              { name: 'quantity', type: 'decimal' },
              { name: 'unit', type: 'select', options: %w[kg lb oz liter gallon pieces] },
              { name: 'reorder_point', type: 'decimal' },
              { name: 'cost_per_unit', type: 'decimal' },
              { name: 'supplier', type: 'string' }
            ]
          }
        ]
      }
    }.freeze

    class << self
      # Detect the archetype from module name/description
      def detect(name:, description: nil)
        search_text = "#{name} #{description}".downcase

        ARCHETYPES.each do |key, archetype|
          triggers = archetype[:triggers]
          match_count = triggers.count { |t| search_text.include?(t) }
          
          # Return if we have 2+ trigger matches (strong signal)
          return { archetype: key, data: archetype, confidence: :high } if match_count >= 2
          
          # Or if the module name directly includes a trigger
          return { archetype: key, data: archetype, confidence: :medium } if triggers.any? { |t| name.downcase.include?(t) }
        end

        # No match found
        { archetype: :custom, data: nil, confidence: :none }
      end

      # Get suggestions for a detected archetype
      def get_suggestions(archetype_key)
        ARCHETYPES[archetype_key.to_sym]
      end

      # Format archetype suggestions for the AI to present
      def format_for_prompt(archetype_key)
        archetype = ARCHETYPES[archetype_key.to_sym]
        return nil unless archetype

        integrations = archetype[:suggested_integrations]&.map { |i| "- **#{i[:name].titleize}**: #{i[:description]}" }&.join("\n")
        
        workflows = archetype[:suggested_workflows]&.map do |w|
          "- **#{w[:name]}**: Triggered when #{w[:trigger].humanize.downcase}"
        end&.join("\n")
        
        scheduled = archetype[:suggested_scheduled_tasks]&.map do |t|
          "- **#{t[:name]}**: #{t[:description]} (#{t[:schedule]})"
        end&.join("\n")

        sub_models_text = if archetype[:sub_models].present?
          models = archetype[:sub_models].map do |sm|
            fields_list = sm[:fields].map { |f| f[:name] }.join(', ')
            "- **#{sm[:name]}**: #{sm[:description]} (#{sm[:relationship][:type]}) — Fields: #{fields_list}"
          end.join("\n")
          <<~SUB

            ### Data Models
            Related data models that will be created:
            #{models}
          SUB
        else
          ''
        end

        <<~SUGGESTIONS
          ## Recommended Setup for #{archetype[:name]}
          #{sub_models_text}
          ### Integrations
          Which platforms should we connect?
          #{integrations}

          ### Automated Workflows
          What should happen automatically?
          #{workflows}

          ### Scheduled Tasks
          What should run on a schedule?
          #{scheduled}

          ---
          Let me know which of these you want, or describe any custom needs.
        SUGGESTIONS
      end

      # Get all archetype keys
      def all_keys
        ARCHETYPES.keys
      end

      # Get sub_models for an archetype (or empty array if none)
      def sub_models_for(archetype_key)
        archetype = ARCHETYPES[archetype_key.to_sym]
        archetype&.dig(:sub_models) || []
      end

      # Get canvas_views for an archetype (or default set)
      def canvas_views_for(archetype_key)
        archetype = ARCHETYPES[archetype_key.to_sym]
        archetype&.dig(:canvas_views) || %w[list form detail]
      end

      # Build a complete module plan spec from archetype, including sub_models
      def build_plan_spec(archetype_key, options = {})
        archetype = ARCHETYPES[archetype_key.to_sym]
        return nil unless archetype

        primary_module = {
          name: archetype[:name],
          slug: archetype_key.to_s,
          fields: archetype[:core_fields] || [],
          canvas_views: archetype[:canvas_views] || %w[list form detail]
        }

        sub_module_specs = (archetype[:sub_models] || []).map do |sm|
          rel = sm[:relationship]
          parent_ref = rel[:type] == 'belongs_to' ? (rel[:parent_model] || archetype_key.to_s) : nil
          
          # Normalize relationship keys: map parent_field -> foreign_key for consistency
          normalized_rel = {
            type: rel[:type],
            foreign_key: rel[:parent_field],
            parent_module_slug: parent_ref,
            parent_model: rel[:parent_model]
          }.compact
          
          {
            name: sm[:name],
            slug: sm[:slug],
            description: sm[:description],
            fields: sm[:fields],
            canvas_views: sm[:canvas_views] || %w[list form],
            relationship: normalized_rel
          }
        end

        {
          primary_module: primary_module,
          sub_modules: sub_module_specs,
          integrations: options[:integrations] || archetype[:suggested_integrations] || [],
          workflows: options[:workflows] || archetype[:suggested_workflows] || [],
          scheduled_tasks: options[:scheduled_tasks] || archetype[:suggested_scheduled_tasks] || []
        }
      end
    end
  end
end

