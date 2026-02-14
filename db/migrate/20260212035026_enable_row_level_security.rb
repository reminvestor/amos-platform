class EnableRowLevelSecurity < ActiveRecord::Migration[8.0]
  # Disable DDL transaction so each table is handled independently
  # This prevents one table's failure from cascading and aborting all subsequent tables
  disable_ddl_transaction!

  # All entity-scoped tables that require RLS policies
  ENTITY_SCOPED_TABLES = %w[
    ab_tests activities agent_ab_tests agent_collaboration_requests
    agent_energy_states agent_energy_transactions agent_goals agent_knowledge_shares
    agent_lifecycle_events agent_lightning_configs agent_lightning_optimizations
    agent_lightning_traces agent_lightning_webhooks agent_llm_calls agent_phase_executions
    agent_plugins agent_reflections agent_relationships agent_rewards
    agent_school_enrollments agent_scratchpads agent_task_proposals agent_tool_executions
    agent_training_jobs agent_work_items ai_rulesets ai_usage_logs
    amos_thinking_sessions analytics_connections analytics_query_logs app_modules
    application_plans apps artifacts automation_codes
    automation_executions benchmark_runs bounties bounty_reviews
    business_insights business_profiles campaigns code_fixes
    commissions community_energy_pools connections contact_groups
    contacts context_graph_stats contributions council_decisions
    council_research_documents crons custom_agent_definitions custom_events
    custom_forms dashboard_widgets deep_research_jobs deep_research_results
    document_indexing_jobs documents education_events email_accounts
    email_messages email_templates engagement_stats entity_memberships
    entity_metrics entity_subscriptions executions execution_histories
    feature_access_requests feature_flags feedback_items file_imports
    free_trial_requests goal_metrics goals industry_analysis_jobs
    industry_analyses industry_reports influencers integration_connections
    integration_credentials integration_logs integration_metrics integration_operations
    integration_syncs integrations internal_transactions inventory_items
    invoices knowledge_base_articles knowledge_bases landing_pages
    lead_magnets leads learning_paths logs
    magic_link_tokens marketplace_listings mastery_trackers meeting_analyses
    meetings mentions menu_items metrics
    migration_logs moderation_logs mute_lists newsletters
    nft_positions nft_transfers notification_preferences onboarding_steps
    opportunities orders payout_requests payouts
    permissions persona_profiles plagiarism_checks plan_comparisons
    platform_agents platform_metrics plugins pricing_rules
    product_categories product_reviews products profiles
    project_milestones projects proposals proposal_signatures
    qualifications rate_limits referral_conversions referrals
    regions report_generations requirements_analyses resource_limits
    resource_usages rewards rulesets schemas
    scratch_pads search_indices segments site_settings
    skills sms_messages social_media_accounts social_posts
    status_updates
    stories stripe_events subscription_change_requests subscription_changes
    subscription_events subscriptions subscriber_tokens table_rulesets
    tags task_attachments task_categories task_comments
    task_dependencies task_sessions task_tags tasks
    team_invitations team_memberships template_instances templates
    threads thumbnails tokens tool_configurations
    tools topic_engagements topic_relationships topics
    transactions trending_topics trusted_devices two_factor_backups
    uploaded_files url_previews voice_calls voice_transcriptions
    wallet_connections webhook_deliveries webhook_events webhooks
    workflow_contexts workflow_executions workflow_histories workflows
  ].freeze

  def up
    # Enable RLS on all entity-scoped tables
    ENTITY_SCOPED_TABLES.each do |table|
      enable_rls_for_table(table)
    end
  end

  def down
    # Disable RLS on all tables
    ENTITY_SCOPED_TABLES.each do |table|
      disable_rls_for_table(table)
    end
  end

  private

  def enable_rls_for_table(table)
    say "Enabling RLS for #{table}..."

    # Enable row level security
    execute "ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY"

    # Force RLS even for table owner (prevents bypassing)
    execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"

    # Create policy that restricts to current entity
    # Policy allows all operations (SELECT, INSERT, UPDATE, DELETE) if entity_id matches
    # NULLIF handles empty string from RESET (converts to NULL, denying all access)
    execute <<-SQL
      CREATE POLICY #{table}_entity_isolation ON #{table}
      FOR ALL
      USING (entity_id = NULLIF(current_setting('app.current_entity_id', true), '')::bigint)
      WITH CHECK (entity_id = NULLIF(current_setting('app.current_entity_id', true), '')::bigint)
    SQL
  rescue ActiveRecord::StatementInvalid => e
    # Log but don't fail if table doesn't exist or already has RLS
    say "Warning: Could not enable RLS for #{table}: #{e.message}", true
  end

  def disable_rls_for_table(table)
    say "Disabling RLS for #{table}..."

    # Drop the policy
    execute "DROP POLICY IF EXISTS #{table}_entity_isolation ON #{table}"

    # Disable RLS
    execute "ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY"
  rescue ActiveRecord::StatementInvalid => e
    # Log but don't fail on rollback
    say "Warning: Could not disable RLS for #{table}: #{e.message}", true
  end
end
