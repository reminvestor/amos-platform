module AbTesting
  # Chi-square test for statistical significance in A/B testing
  # Tests the null hypothesis that conversion rates are the same across variants
  class ChiSquareTest
    attr_reader :variants

    def initialize(variants)
      @variants = variants
    end

    # Check if results are statistically significant
    # @param confidence [Float] Confidence level (e.g., 0.95 for 95%)
    # @return [Boolean] True if statistically significant
    def significant?(confidence = 0.95)
      return false if variants.count < 2
      return false if variants.any? { |v| v.impressions < 10 }

      chi_square_statistic = calculate_chi_square
      critical_value = critical_value_for_confidence(confidence, degrees_of_freedom)

      chi_square_statistic > critical_value
    end

    # Calculate the Chi-square statistic
    # χ² = Σ [(Observed - Expected)² / Expected]
    def calculate_chi_square
      total_impressions = variants.sum(&:impressions)
      total_conversions = variants.sum(&:conversions)
      total_non_conversions = total_impressions - total_conversions

      return 0 if total_impressions.zero?

      # Overall conversion rate (expected under null hypothesis)
      overall_rate = total_conversions.to_f / total_impressions

      chi_square = 0.0

      variants.each do |variant|
        # Expected conversions and non-conversions for this variant
        expected_conversions = variant.impressions * overall_rate
        expected_non_conversions = variant.impressions * (1 - overall_rate)

        # Observed values
        observed_conversions = variant.conversions
        observed_non_conversions = variant.impressions - variant.conversions

        # Avoid division by zero
        next if expected_conversions.zero? || expected_non_conversions.zero?

        # Chi-square contribution from conversions
        chi_square += ((observed_conversions - expected_conversions) ** 2) / expected_conversions

        # Chi-square contribution from non-conversions
        chi_square += ((observed_non_conversions - expected_non_conversions) ** 2) / expected_non_conversions
      end

      chi_square
    end

    # P-value approximation
    def p_value
      chi_square = calculate_chi_square
      df = degrees_of_freedom

      # Simplified p-value calculation
      # For more accuracy, use a statistics library
      # This is a rough approximation
      return 1.0 if chi_square.zero?

      # Very rough approximation using chi-square to p-value mapping
      case chi_square
      when 0..3.84
        0.05..1.0 # Not significant
      when 3.84..6.63
        0.01..0.05 # Marginally significant
      when 6.63..10.83
        0.001..0.01 # Significant
      else
        0.0..0.001 # Highly significant
      end.min
    end

    # Effect size (Cramér's V)
    def effect_size
      chi_square = calculate_chi_square
      n = variants.sum(&:impressions)
      k = variants.count

      return 0 if n.zero? || k <= 1

      Math.sqrt(chi_square / (n * (k - 1)))
    end

    # Interpretation of effect size
    def effect_interpretation
      v = effect_size

      case v
      when 0..0.1
        'negligible'
      when 0.1..0.3
        'small'
      when 0.3..0.5
        'medium'
      else
        'large'
      end
    end

    private

    def degrees_of_freedom
      # df = (number of variants - 1) * (number of outcomes - 1)
      # For binary outcome (conversion vs no conversion): (k - 1) * 1 = k - 1
      variants.count - 1
    end

    # Critical values for Chi-square distribution
    # Source: Chi-square distribution table
    def critical_value_for_confidence(confidence, df)
      # Map confidence level to alpha (significance level)
      alpha = 1 - confidence

      # Chi-square critical values table
      # Rows: degrees of freedom, Columns: alpha levels
      critical_values = {
        0.10 => [2.71, 4.61, 6.25, 7.78, 9.24, 10.64, 12.02, 13.36, 14.68, 15.99],
        0.05 => [3.84, 5.99, 7.81, 9.49, 11.07, 12.59, 14.07, 15.51, 16.92, 18.31],
        0.01 => [6.63, 9.21, 11.34, 13.28, 15.09, 16.81, 18.48, 20.09, 21.67, 23.21],
        0.001 => [10.83, 13.82, 16.27, 18.47, 20.52, 22.46, 24.32, 26.12, 27.88, 29.59]
      }

      # Find closest alpha level
      closest_alpha = critical_values.keys.min_by { |a| (a - alpha).abs }

      # Get critical value for df (capped at 10)
      df_index = [df - 1, 9].min
      critical_values[closest_alpha][df_index] || critical_values[closest_alpha].last
    end
  end
end
