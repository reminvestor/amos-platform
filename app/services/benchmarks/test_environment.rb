# frozen_string_literal: true

module Benchmarks
  # Manages the isolated test environment for benchmarks
  # Provides a dedicated entity/user and handles cleanup between runs
  class TestEnvironment
    BENCHMARK_ENTITY_SLUG = 'benchmark_test'
    BENCHMARK_USER_EMAIL = 'benchmark@amoslabs.internal'

    class << self
      # Get or create the benchmark test entity
      def entity
        @entity ||= find_or_create_entity!
      end

      # Get or create the benchmark test user
      def user
        @user ||= find_or_create_user!
      end

      # Reset cached instances (useful after cleanup)
      def reset!
        @entity = nil
        @user = nil
      end

      # Clean up all test data before a benchmark run
      # This ensures fresh, reproducible results
      def cleanup!(options = {})
        Rails.logger.info "[Benchmark] Starting test environment cleanup..."
        
        cleanup_stats = {
          integrations: 0,
          agents: 0,
          tools: 0,
          landing_pages: 0,
          email_campaigns: 0,
          executions: 0,
          benchmark_runs: 0
        }

        ActiveRecord::Base.transaction do
          # Delete integrations created by benchmark entity
          if options[:integrations] != false
            count = Integration.where(entity_id: entity.id).destroy_all.count
            count += Integration.where(created_by_id: user.id).destroy_all.count
            cleanup_stats[:integrations] = count
          end

          # Delete agent plugins created by benchmark entity
          if options[:agents] != false
            # Only delete agents created specifically for this benchmark entity
            # Don't delete agents that might be shared/system agents
            count = AgentPlugin.where(entity: entity)
                               .where('created_at > ?', 1.day.ago) # Only recent ones
                               .destroy_all.count
            cleanup_stats[:agents] = count
          end

          # Delete tool definitions created by benchmark user
          # First delete any tool_usage_metrics that reference these tools (FK constraint)
          if options[:tools] != false
            tool_ids = ToolDefinition.where(created_by: user).pluck(:id)
            if tool_ids.any?
              # Use raw SQL to handle FK constraint - delete metrics first
              ActiveRecord::Base.connection.execute(
                "DELETE FROM tool_usage_metrics WHERE tool_definition_id IN (#{tool_ids.join(',')})"
              ) rescue nil
            end
            count = ToolDefinition.where(created_by: user).destroy_all.count
            cleanup_stats[:tools] = count
          end

          # Delete landing pages
          if options[:landing_pages] != false && defined?(LandingPage)
            count = LandingPage.where(entity: entity).destroy_all.count
            cleanup_stats[:landing_pages] = count
          end

          # Delete email campaigns
          if options[:email_campaigns] != false && defined?(Campaign)
            count = Campaign.where(entity: entity).destroy_all.count
            cleanup_stats[:email_campaigns] = count
          end

          # Delete agent executions (keep for history unless explicitly requested)
          if options[:executions] == true
            count = AgentPluginExecution.joins(:agent_plugin)
                                        .where(agent_plugins: { entity_id: entity.id })
                                        .destroy_all.count
            cleanup_stats[:executions] = count
          end

          # Optionally delete old benchmark runs (keep by default for trending)
          if options[:benchmark_runs] == true
            count = BenchmarkRun.where(entity: entity).destroy_all.count
            cleanup_stats[:benchmark_runs] = count
          end
        end

        Rails.logger.info "[Benchmark] Cleanup complete: #{cleanup_stats.inspect}"
        cleanup_stats
      end

      # Check if the test environment is properly set up
      def ready?
        entity.present? && user.present?
      rescue
        false
      end

      # Get summary of current test data
      def status
        {
          entity_id: entity&.id,
          entity_name: entity&.name,
          user_id: user&.id,
          user_email: user&.email,
          data_counts: {
            integrations: Integration.where(entity_id: entity&.id).count + 
                          Integration.where(created_by_id: user&.id).count,
            agents: AgentPlugin.where(entity: entity).count,
            tools: ToolDefinition.where(created_by: user).count,
            executions: AgentPluginExecution.joins(:agent_plugin).where(agent_plugins: { entity_id: entity&.id }).count,
            benchmark_runs: BenchmarkRun.where(entity: entity).count
          }
        }
      rescue => e
        { error: e.message }
      end

      private

      def find_or_create_entity!
        Entity.find_by(slug: BENCHMARK_ENTITY_SLUG) || create_entity!
      end

      def create_entity!
        Entity.create!(
          name: 'Benchmark Test Entity',
          slug: BENCHMARK_ENTITY_SLUG,
          subdomain: 'benchmark-test',
          settings: {
            'is_benchmark_entity' => true,
            'auto_cleanup' => true,
            'created_for' => 'automated_benchmarks'
          }
        )
      end

      def find_or_create_user!
        User.find_by(email: BENCHMARK_USER_EMAIL) || create_user!
      end

      def create_user!
        user = User.create!(
          email: BENCHMARK_USER_EMAIL,
          first_name: 'Benchmark',
          last_name: 'Runner',
          password: SecureRandom.hex(16) + 'Aa1!',  # Random password meeting requirements
          role: 'admin',  # Valid roles: admin, marketer, viewer
          entity: entity
        )

        # Create entity membership if the model exists
        if defined?(EntityMembership)
          EntityMembership.find_or_create_by!(user: user, entity: entity) do |m|
            m.role = 'owner'
          end
        end

        user
      end
    end
  end
end

