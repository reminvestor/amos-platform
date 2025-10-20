module AbTesting
  # Service for running A/B test experiments
  # Handles variant selection, tracking, and winner determination
  class ExperimentService
    # Select a variant for a given user/request
    # Uses consistent hashing to ensure same user always gets same variant
    #
    # @param ab_test [AbTest] The A/B test
    # @param identifier [String] Unique identifier (user_id, email, session_id, etc.)
    # @return [AbTestVariant] The selected variant
    def self.select_variant(ab_test, identifier)
      return nil unless ab_test&.status == 'running'
      return nil if ab_test.variants.empty?

      # Use MD5 hash for consistent variant assignment
      hash_value = Digest::MD5.hexdigest("#{ab_test.id}-#{identifier}").to_i(16)
      random_value = (hash_value % 10000) / 100.0 # 0.00 to 99.99

      # Assign variant based on traffic percentage
      cumulative_percentage = 0.0
      ab_test.variants.each do |variant|
        cumulative_percentage += variant.traffic_percentage
        return variant if random_value < cumulative_percentage
      end

      # Fallback to first variant (shouldn't happen if percentages sum to 100)
      ab_test.variants.first
    end

    # Track an impression (variant was shown)
    #
    # @param variant [AbTestVariant] The variant that was shown
    # @return [Boolean] Success
    def self.track_impression(variant)
      return false unless variant

      variant.record_impression!

      # Check if test should auto-complete
      check_auto_complete(variant.ab_test)

      true
    rescue => e
      Rails.logger.error "[AbTesting] Failed to track impression: #{e.message}"
      false
    end

    # Track a conversion (user completed the goal)
    #
    # @param variant [AbTestVariant] The variant the user saw
    # @return [Boolean] Success
    def self.track_conversion(variant)
      return false unless variant

      variant.record_conversion!

      # Check if test should auto-complete
      check_auto_complete(variant.ab_test)

      true
    rescue => e
      Rails.logger.error "[AbTesting] Failed to track conversion: #{e.message}"
      false
    end

    # Get variant for tracking (by test and identifier)
    #
    # @param ab_test [AbTest] The A/B test
    # @param identifier [String] User identifier
    # @return [AbTestVariant, nil] The variant or nil
    def self.get_variant_for_tracking(ab_test, identifier)
      select_variant(ab_test, identifier)
    end

    # Check if test should auto-complete based on criteria
    #
    # @param ab_test [AbTest] The test to check
    # @return [Boolean] True if completed
    def self.check_auto_complete(ab_test)
      return false unless ab_test.status == 'running'
      return false unless ab_test.metadata['auto_complete_enabled']

      # Check if minimum sample size reached
      if ab_test.has_sufficient_data?
        # Check if there's a clear winner
        winner = ab_test.calculate_winner

        if winner
          Rails.logger.info "[AbTesting] Auto-completing test #{ab_test.id}: winner found"
          ab_test.complete!
          return true
        end
      end

      # Check if maximum duration exceeded
      max_days = ab_test.metadata['max_days_to_run']
      if max_days && ab_test.days_running >= max_days
        Rails.logger.info "[AbTesting] Auto-completing test #{ab_test.id}: max duration reached"
        ab_test.complete!(force: true)
        return true
      end

      false
    end

    # Create a simple two-variant test
    #
    # @param entity [Entity] The entity
    # @param testable [Object] The object being tested (Campaign, LandingPage, etc.)
    # @param name [String] Test name
    # @param control_config [Hash] Configuration for control variant
    # @param variant_config [Hash] Configuration for test variant
    # @return [AbTest] The created test
    def self.create_simple_test(entity:, testable:, name:, hypothesis: nil, control_config: {}, variant_config: {})
      test = AbTest.create!(
        entity: entity,
        testable: testable,
        name: name,
        hypothesis: hypothesis,
        status: 'draft',
        confidence_level: 0.95,
        minimum_sample_size: 100
      )

      # Create control variant (A)
      test.variants.create!(
        name: 'Control (A)',
        traffic_percentage: 50.0,
        configuration: control_config,
        is_control: true
      )

      # Create test variant (B)
      test.variants.create!(
        name: 'Variant (B)',
        traffic_percentage: 50.0,
        configuration: variant_config
      )

      test
    end

    # Create a multi-variant test
    #
    # @param entity [Entity] The entity
    # @param testable [Object] The object being tested
    # @param name [String] Test name
    # @param variants_config [Array<Hash>] Array of variant configurations
    # @return [AbTest] The created test
    def self.create_multi_variant_test(entity:, testable:, name:, hypothesis: nil, variants_config:)
      test = AbTest.create!(
        entity: entity,
        testable: testable,
        name: name,
        hypothesis: hypothesis,
        status: 'draft',
        confidence_level: 0.95,
        minimum_sample_size: 100 * variants_config.count # Scale sample size with variants
      )

      # Distribute traffic evenly by default
      traffic_per_variant = (100.0 / variants_config.count).round(2)

      variants_config.each_with_index do |config, index|
        test.variants.create!(
          name: config[:name] || "Variant #{('A'.ord + index).chr}",
          traffic_percentage: config[:traffic_percentage] || traffic_per_variant,
          configuration: config[:configuration] || {},
          is_control: index.zero? # First variant is control
        )
      end

      test
    end

    # Get test results summary
    #
    # @param ab_test [AbTest] The test
    # @return [Hash] Results summary
    def self.get_results_summary(ab_test)
      chi_square = ChiSquareTest.new(ab_test.variants)

      {
        test_id: ab_test.id,
        test_name: ab_test.name,
        status: ab_test.status,
        started_at: ab_test.started_at,
        ended_at: ab_test.ended_at,
        days_running: ab_test.days_running,
        total_impressions: ab_test.total_impressions,
        total_conversions: ab_test.total_conversions,
        overall_conversion_rate: ab_test.overall_conversion_rate,
        progress_percentage: ab_test.progress_percentage,
        has_sufficient_data: ab_test.has_sufficient_data?,
        is_significant: chi_square.significant?(ab_test.confidence_level),
        chi_square_statistic: chi_square.calculate_chi_square.round(4),
        effect_size: chi_square.effect_size.round(4),
        effect_interpretation: chi_square.effect_interpretation,
        current_leader: ab_test.current_leader&.name,
        winner: ab_test.results&.dig('winner_name'),
        variants: ab_test.variants.map do |v|
          {
            id: v.id,
            name: v.name,
            is_control: v.is_control,
            is_winner: v.is_winner,
            traffic_percentage: v.traffic_percentage,
            impressions: v.impressions,
            conversions: v.conversions,
            conversion_rate: v.conversion_rate,
            uplift_vs_control: v.uplift_vs_control,
            confidence_score: v.confidence_score
          }
        end
      }
    end
  end
end
