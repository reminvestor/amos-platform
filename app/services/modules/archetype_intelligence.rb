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
        ]
      },

      # ========================================
      # CRM / SALES
      # ========================================
      crm: {
        triggers: %w[crm sales leads pipeline deals opportunities customers contacts],
        name: 'CRM / Sales Pipeline',
        description: 'Track leads, deals, and customer relationships',
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
        ]
      },

      # ========================================
      # PROJECT MANAGEMENT
      # ========================================
      project: {
        triggers: %w[project task milestone sprint kanban agile workflow team],
        name: 'Project Management',
        description: 'Track projects, tasks, and team progress',
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
        special_features: ['public_portal', 'search_embedding', 'version_history']
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

        <<~SUGGESTIONS
          ## Recommended Setup for #{archetype[:name]}

          ### 🔌 Integrations
          Which platforms should we connect?
          #{integrations}

          ### ⚡ Automated Workflows
          What should happen automatically?
          #{workflows}

          ### 📅 Scheduled Tasks
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
    end
  end
end

