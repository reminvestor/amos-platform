# frozen_string_literal: true

module Benchmarks
  module V2
    # ScenarioLibrary - Explicit registry of all benchmark scenarios
    #
    # V3 pattern: simple hash, add a scenario = add one line.
    # Scenarios are organized by level and category.
    #
    # Usage:
    #   ScenarioLibrary.all
    #   ScenarioLibrary.core_suite          # Post-deploy quick check
    #   ScenarioLibrary.by_level(:L3)
    #   ScenarioLibrary.by_category(:app_building)
    #
    class ScenarioLibrary
      class << self
        def all
          SCENARIOS.values
        end

        def get(id)
          SCENARIOS[id]
        end

        def core_suite
          all.select(&:core?)
        end

        def by_level(level)
          all.select { |s| s.level == level }
        end

        def by_category(category)
          all.select { |s| s.category == category }
        end

        def by_source(source)
          all.select { |s| s.source == source }
        end

        def ids
          SCENARIOS.keys
        end

        def count
          SCENARIOS.size
        end
      end

      # All registered scenarios -- add new scenarios here
      SCENARIOS = {
        # ═══════════════════════════════════════════════════════════
        # L2: Multi-step workflows (the new baseline difficulty)
        # ═══════════════════════════════════════════════════════════

        landing_page_multi_section: Scenarios::LandingPageMultiSection.build,
        email_sequence_creation: Scenarios::EmailSequenceCreation.build,
        contact_import_and_campaign: Scenarios::ContactImportAndCampaign.build,

        # ═══════════════════════════════════════════════════════════
        # L3: Complex orchestration (what real users do)
        # ═══════════════════════════════════════════════════════════

        app_build_multi_module: Scenarios::AppBuildMultiModule.build,
        data_analysis_and_report: Scenarios::DataAnalysisAndReport.build,
        email_sequence_full_lifecycle: Scenarios::EmailSequenceFullLifecycle.build,
        integration_discovery_and_use: Scenarios::IntegrationDiscoveryAndUse.build,
        cross_platform_workflow: Scenarios::CrossPlatformWorkflow.build,

        # ═══════════════════════════════════════════════════════════
        # L4: Adversarial / edge cases (what breaks in production)
        # ═══════════════════════════════════════════════════════════

        ambiguous_request_handling: Scenarios::AmbiguousRequestHandling.build,
        nonexistent_data_graceful: Scenarios::NonexistentDataGraceful.build,
        error_recovery_mid_workflow: Scenarios::ErrorRecoveryMidWorkflow.build,
        integration_error_graceful: Scenarios::IntegrationErrorGraceful.build,
      }.freeze
    end
  end
end
