class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Email deliveries - frequently queried by campaign and status
    unless index_exists?(:email_deliveries, [:campaign_id, :status, :sent_at])
      add_index :email_deliveries, [:campaign_id, :status, :sent_at],
                name: 'index_email_deliveries_on_campaign_status_sent'
    end

    # Workflow contexts - queried by execution and phase
    unless index_exists?(:workflow_contexts, [:workflow_execution_id, :phase])
      add_index :workflow_contexts, [:workflow_execution_id, :phase],
                name: 'index_workflow_contexts_on_execution_phase'
    end

    # Affiliate clicks - frequently queried for analytics
    if table_exists?(:affiliate_clicks)
      unless index_exists?(:affiliate_clicks, [:affiliate_id, :landed_at])
        add_index :affiliate_clicks, [:affiliate_id, :landed_at],
                  name: 'index_affiliate_clicks_on_affiliate_landed'
      end
    end

    # Contacts - improve entity scoping and engagement queries
    unless index_exists?(:contacts, [:entity_id, :status])
      add_index :contacts, [:entity_id, :status],
                name: 'index_contacts_on_entity_status'
    end

    unless index_exists?(:contacts, [:entity_id, :lead])
      add_index :contacts, [:entity_id, :lead],
                name: 'index_contacts_on_entity_lead'
    end

    # Campaigns - frequently filtered by entity and status
    unless index_exists?(:campaigns, [:entity_id, :status])
      add_index :campaigns, [:entity_id, :status],
                name: 'index_campaigns_on_entity_status'
    end

    # Landing pages - slug lookups and entity filtering
    unless index_exists?(:landing_pages, [:slug])
      add_index :landing_pages, [:slug], unique: true,
                name: 'index_landing_pages_on_slug'
    end

    unless index_exists?(:landing_pages, [:entity_id, :status])
      add_index :landing_pages, [:entity_id, :status],
                name: 'index_landing_pages_on_entity_status'
    end

    # Integration logs - frequently queried for monitoring
    if table_exists?(:integration_logs)
      unless index_exists?(:integration_logs, [:connection_id, :created_at])
        add_index :integration_logs, [:connection_id, :created_at],
                  name: 'index_integration_logs_on_connection_created'
      end

      unless index_exists?(:integration_logs, [:status])
        add_index :integration_logs, [:status],
                  name: 'index_integration_logs_on_status'
      end
    end
  end
end
