# Shared concern for parsing JSON responses from LLMs
module LlmJsonParser
  extend ActiveSupport::Concern
  
  # Standardized JSON format instructions for LLM prompts
  JSON_FORMAT_INSTRUCTIONS = <<~INSTRUCTIONS.freeze
    CRITICAL JSON FORMAT REQUIREMENTS:
    1. Return ONLY raw JSON - no markdown, no code blocks, no backticks
    2. No text before or after the JSON
    3. No ```json or ``` wrappers
    4. Must be valid, parseable JSON
    5. JSON must start with { or [ and end with } or ]
  INSTRUCTIONS
  
  class_methods do
    # Parse JSON from LLM response with standardized error handling
    def parse_json_from_llm(response, context: nil)
      # Expected format: raw JSON starting with { or [ and ending with } or ]
      # But sometimes LLMs wrap JSON in markdown code blocks despite instructions
      cleaned_response = response.strip
      
      # Check if response is wrapped in markdown code blocks
      if cleaned_response.start_with?("```json") || cleaned_response.start_with?("```")
        Rails.logger.warn "[#{context || 'LlmJsonParser'}] LLM returned markdown-wrapped JSON despite instructions. Stripping wrappers..."
        # Remove opening code block
        cleaned_response = cleaned_response.sub(/^```(?:json)?\s*\n?/, '')
        # Remove closing code block
        cleaned_response = cleaned_response.sub(/\n?```\s*$/, '')
      end
      
      # Validate JSON starts and ends correctly
      unless (cleaned_response.start_with?('{') && cleaned_response.end_with?('}')) || 
             (cleaned_response.start_with?('[') && cleaned_response.end_with?(']'))
        Rails.logger.warn "[#{context || 'LlmJsonParser'}] Response doesn't start/end with JSON brackets. First 50 chars: #{cleaned_response[0..50]}"
      end
      
      begin
        result = JSON.parse(cleaned_response, symbolize_names: true)
        Rails.logger.info "[#{context || 'LlmJsonParser'}] Successfully parsed JSON response"
        result
      rescue JSON::ParserError => e
        Rails.logger.error "[#{context || 'LlmJsonParser'}] JSON parsing failed. First 200 chars: #{cleaned_response[0..200]}"
        Rails.logger.error "[#{context || 'LlmJsonParser'}] Parse error: #{e.message}"
        raise e
      end
    end
  end
  
  included do
    # Instance method version for convenience
    def parse_json_from_llm(response, context: nil)
      self.class.parse_json_from_llm(response, context: context || self.class.name)
    end
  end
end
