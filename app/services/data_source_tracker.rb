# frozen_string_literal: true

# DataSourceTracker - CaMeL-style data provenance tracking
#
# Tracks where each piece of data originated so security policies can make
# informed decisions about what actions to allow without user confirmation.
#
# Based on the CaMeL paper: "Defeating Prompt Injections by Design"
# https://simonwillison.net/2025/Apr/11/camel/
#
# Usage:
#   tagged = DataSourceTracker.tag(email_content, source: :email)
#   DataSourceTracker.trusted?(tagged)  # => false
#
#   tagged = DataSourceTracker.tag(user_input, source: :user_prompt)
#   DataSourceTracker.trusted?(tagged)  # => true
#
class DataSourceTracker
  # Trust levels for different data sources
  # :trusted    - Direct user input, system-generated data
  # :untrusted  - External data that could contain prompt injection
  # :derived    - Extracted/processed from untrusted sources
  TRUST_LEVELS = {
    # Trusted sources - user directly provided or system generated
    user_prompt: :trusted,
    user_confirmation: :trusted,
    system: :trusted,
    platform: :trusted,
    
    # Untrusted sources - external data that could be malicious
    tool_result: :untrusted,
    document: :untrusted,
    email: :untrusted,
    email_body: :untrusted,
    integration: :untrusted,
    api_response: :untrusted,
    webhook: :untrusted,
    rag_content: :untrusted,
    web_scrape: :untrusted,
    file_upload: :untrusted,
    
    # Derived - extracted from untrusted sources via Q-LLM
    extracted: :derived,
    quarantined_extraction: :derived
  }.freeze

  # Tools that produce untrusted data
  UNTRUSTED_TOOL_RESULTS = %w[
    get_data
    search_documents
    query_rag_store
    execute_integration
    web_search
    read_email
    get_document_content
    fetch_url
  ].freeze

  # Tools that perform sensitive actions requiring trust verification
  SENSITIVE_TOOLS = %w[
    send_email
    create_object
    update_object
    delete_object
    execute_integration
    publish_app
    create_contact
    update_contact
  ].freeze

  class << self
    # Tag data with its source information
    # @param data [Any] The data to tag
    # @param source [Symbol] The source type (see TRUST_LEVELS)
    # @param parent_sources [Array] Sources this data was derived from
    # @param metadata [Hash] Additional tracking metadata
    # @return [Hash] Tagged data wrapper
    def tag(data, source:, parent_sources: [], metadata: {})
      trust_level = determine_trust_level(source, parent_sources)
      
      {
        _tagged: true,
        value: data,
        source: source.to_sym,
        trust_level: trust_level,
        parent_sources: parent_sources,
        tagged_at: Time.current.iso8601,
        metadata: metadata
      }
    end

    # Check if tagged data is trusted
    # @param tagged_data [Hash] Tagged data from .tag()
    # @return [Boolean]
    def trusted?(tagged_data)
      return true unless tagged?(tagged_data)
      tagged_data[:trust_level] == :trusted
    end

    # Check if tagged data is untrusted
    # @param tagged_data [Hash] Tagged data from .tag()
    # @return [Boolean]
    def untrusted?(tagged_data)
      return false unless tagged?(tagged_data)
      tagged_data[:trust_level] == :untrusted
    end

    # Check if tagged data is derived (from Q-LLM extraction)
    # @param tagged_data [Hash] Tagged data from .tag()
    # @return [Boolean]
    def derived?(tagged_data)
      return false unless tagged?(tagged_data)
      tagged_data[:trust_level] == :derived
    end

    # Check if data has been tagged
    # @param data [Any]
    # @return [Boolean]
    def tagged?(data)
      data.is_a?(Hash) && data[:_tagged] == true
    end

    # Extract the raw value from tagged data
    # @param tagged_data [Hash] Tagged data
    # @return [Any] The original value
    def unwrap(tagged_data)
      return tagged_data unless tagged?(tagged_data)
      tagged_data[:value]
    end

    # Tag tool results based on tool name
    # @param tool_name [String] Name of the tool that produced the result
    # @param result [Hash] The tool's result
    # @return [Hash] Tagged result
    def tag_tool_result(tool_name, result)
      source = if UNTRUSTED_TOOL_RESULTS.include?(tool_name.to_s)
                 :tool_result
               else
                 :system
               end
      
      tag(result, source: source, metadata: { tool_name: tool_name })
    end

    # Check if a tool is sensitive (requires trust verification)
    # @param tool_name [String]
    # @return [Boolean]
    def sensitive_tool?(tool_name)
      SENSITIVE_TOOLS.include?(tool_name.to_s)
    end

    # Collect all data sources from a context/args hash
    # @param data [Hash] Arguments or context containing potentially tagged data
    # @return [Array<Hash>] Array of source information
    def collect_sources(data)
      sources = []
      
      traverse_and_collect(data) do |tagged|
        sources << {
          source: tagged[:source],
          trust_level: tagged[:trust_level],
          tagged_at: tagged[:tagged_at]
        }
      end
      
      sources.uniq
    end

    # Check if any data in the context is untrusted
    # @param data [Hash] Arguments or context
    # @return [Boolean]
    def has_untrusted?(data)
      found_untrusted = false
      
      traverse_and_collect(data) do |tagged|
        found_untrusted = true if tagged[:trust_level] == :untrusted
      end
      
      found_untrusted
    end

    # Promote derived data to trusted (after user confirmation)
    # @param tagged_data [Hash] Tagged data
    # @return [Hash] New tagged data with trusted status
    def promote_to_trusted(tagged_data)
      return tagged_data unless tagged?(tagged_data)
      
      tagged_data.merge(
        trust_level: :trusted,
        promoted_at: Time.current.iso8601,
        original_trust_level: tagged_data[:trust_level]
      )
    end

    private

    def determine_trust_level(source, parent_sources)
      # If any parent is untrusted, derived data is also considered derived/untrusted
      if parent_sources.any? { |ps| ps[:trust_level] == :untrusted }
        return :derived
      end
      
      TRUST_LEVELS[source.to_sym] || :untrusted
    end

    def traverse_and_collect(data, &block)
      case data
      when Hash
        if tagged?(data)
          yield data
        else
          data.each_value { |v| traverse_and_collect(v, &block) }
        end
      when Array
        data.each { |item| traverse_and_collect(item, &block) }
      end
    end
  end
end
