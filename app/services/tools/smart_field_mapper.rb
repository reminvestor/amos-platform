# frozen_string_literal: true

module Tools
  # SmartFieldMapper - Auto-corrects common field naming mistakes
  #
  # When LLMs generate data for creating/updating records, they often use
  # slightly wrong field names (e.g., "lifecycle_stage" vs "stage"). 
  # This mapper attempts to correct these automatically.
  #
  class SmartFieldMapper
    # Common field name corrections
    FIELD_MAPPINGS = {
      # Contact fields
      "lifecycle_stage" => "stage",
      "lifecyclestage" => "stage",
      "life_cycle_stage" => "stage",
      "subscription_status" => "status",
      "subscriber_status" => "status",
      "firstname" => "first_name",
      "lastname" => "last_name",
      "emailaddress" => "email",
      "email_address" => "email",
      "phonenumber" => "phone",
      "phone_number" => "phone",
      
      # Common typos
      "statut" => "status",
      "emial" => "email",
      "frist_name" => "first_name",
      "lats_name" => "last_name",
    }.freeze

    # Map input data, correcting field names where possible
    # @param data [Hash] The input data with potentially incorrect field names
    # @return [Hash] { corrected_data: Hash, corrections: Array }
    def map_data(data)
      return { corrected_data: data || {}, corrections: [] } if data.blank?

      corrected = {}
      corrections = []

      data.each do |key, value|
        key_str = key.to_s.downcase.strip
        
        if FIELD_MAPPINGS.key?(key_str)
          corrected_key = FIELD_MAPPINGS[key_str]
          corrected[corrected_key] = value
          corrections << {
            original_field: key.to_s,
            original_value: value,
            corrected_field: corrected_key,
            corrected_value: value
          }
        else
          # Keep the original key (but normalize to string)
          corrected[key.to_s] = value
        end
      end

      {
        corrected_data: corrected,
        corrections: corrections
      }
    end
  end
end
