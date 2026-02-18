# frozen_string_literal: true

# CsvColumnMapperService
#
# Intelligently maps CSV column headers to contact fields.
# Uses a two-tier approach:
#   1. Fast regex matching for common formats (Google Contacts, Outlook, etc.)
#   2. LLM fallback for unknown formats - analyzes headers + sample data
#
# The mapping is computed once per import and reused for all rows.
#
class CsvColumnMapperService
  CONTACT_FIELDS = {
    email: { required: true, description: "Email address" },
    first_name: { required: false, description: "First/given name" },
    last_name: { required: false, description: "Last/family/surname" },
    phone: { required: false, description: "Phone number" },
    company: { required: false, description: "Company or organization name" },
    tags: { required: false, description: "Tags or labels" },
    lifecycle_stage: { required: false, description: "Contact lifecycle stage" },
    lead_source: { required: false, description: "How the contact was acquired" }
  }.freeze

  # Patterns for regex-based matching (checked in order, first match wins)
  REGEX_PATTERNS = {
    email: [
      /\A(email|e_mail|email_address|emailaddress)\z/i,
      /e?mail.*value/i,
      /email_?\d/i,
      /primary.*e?mail/i,
      /\Aemial\z/i  # common typo
    ],
    first_name: [
      /\A(first_name|firstname|first|given_name|givenname)\z/i,
      /\Afrist_name\z/i  # common typo
    ],
    last_name: [
      /\A(last_name|lastname|last|family_name|familyname|surname)\z/i,
      /\Alats_name\z/i  # common typo
    ],
    phone: [
      /\A(phone|phone_number|phonenumber|mobile|cell|telephone)\z/i,
      /phone.*value/i
    ],
    company: [
      /\A(company|organization|organisation|company_name|org|employer)\z/i,
      /organization.*(?:name|value)/i
    ],
    tags: [
      /\A(tags?|labels?|categories)\z/i,
      /\Agroup_membership\z/i
    ],
    lifecycle_stage: [
      /\A(lifecycle_stage|life_cycle_stage|stage|status)\z/i
    ],
    lead_source: [
      /\A(lead_source|source|referral_source|how_did_you_hear)\z/i
    ]
  }.freeze

  # Special: a "name" column that needs splitting
  NAME_PATTERN = /\A(name|full_name|fullname|display_name)\z/i

  def initialize(headers:, sample_rows: [], entity: nil)
    @headers = headers.map(&:to_s)
    @sample_rows = sample_rows
    @entity = entity
    @mapping = {}
  end

  # Returns a mapping hash: { our_field_symbol => csv_header_string, ... }
  # Also returns :name_column if a combined name field was detected.
  def compute_mapping
    @mapping = {}

    # Tier 1: regex matching
    regex_match

    # Check if we found the required email field
    if @mapping[:email].present?
      Rails.logger.info "📋 CsvColumnMapper: Regex matched email → '#{@mapping[:email]}'"
      log_mapping("regex")
      return @mapping
    end

    # Tier 2: LLM-based matching
    Rails.logger.info "📋 CsvColumnMapper: Regex missed email, falling back to LLM"
    llm_match

    log_mapping("llm")
    @mapping
  end

  private

  def regex_match
    REGEX_PATTERNS.each do |field, patterns|
      next if @mapping[field].present?

      @headers.each do |header|
        if patterns.any? { |p| header.match?(p) }
          @mapping[field] = header
          break
        end
      end
    end

    # Check for combined name column
    @headers.each do |header|
      if header.match?(NAME_PATTERN) && @mapping[:first_name].blank? && @mapping[:last_name].blank?
        @mapping[:name_column] = header
        break
      end
    end
  end

  def llm_match
    prompt = build_llm_prompt
    response = call_llm(prompt)
    parse_llm_response(response)
  rescue => e
    Rails.logger.error "📋 CsvColumnMapper LLM error: #{e.message}"
  end

  def build_llm_prompt
    sample_data = @sample_rows.first(3).map do |row|
      row.map { |k, v| "#{k}: #{v}" }.join(", ")
    end.join("\n")

    <<~PROMPT
      You are a data mapping assistant. Given CSV column headers and sample data, map them to contact fields.

      CSV HEADERS: #{@headers.join(', ')}

      SAMPLE DATA (first 3 rows):
      #{sample_data}

      MAP TO THESE FIELDS (return only the ones you can confidently match):
      - email (REQUIRED - the contact's email address)
      - first_name (first/given name)
      - last_name (last/family name)
      - phone (phone number)
      - company (company/organization name)
      - tags (tags, labels, or categories)
      - lead_source (how the contact was acquired)
      - name_column (a combined full name field, only if no separate first/last name columns exist)

      Respond with ONLY a JSON object mapping our field names to the exact CSV header name.
      Example: {"email": "E-mail 1 - Value", "first_name": "Given Name", "last_name": "Family Name"}

      If a field cannot be confidently matched, omit it. The email field is the most important.
    PROMPT
  end

  def call_llm(prompt)
    bedrock = BedrockService.new(entity: @entity)
    response = bedrock.send_message(
      "You are a precise data mapping assistant. Respond with only valid JSON, no explanation.",
      [{ role: "user", content: prompt }],
      model: "claude-haiku-4-5",
      max_tokens: 500,
      temperature: 0
    )
    response.to_s.strip
  end

  def parse_llm_response(response)
    return if response.blank?

    json_match = response.match(/\{[^}]+\}/)
    return unless json_match

    mapping = JSON.parse(json_match[0])

    mapping.each do |our_field, csv_header|
      field_sym = our_field.to_sym
      next unless CONTACT_FIELDS.key?(field_sym) || field_sym == :name_column

      # Verify the header actually exists in the CSV
      matched_header = @headers.find { |h| h.casecmp?(csv_header.to_s) }
      if matched_header
        @mapping[field_sym] = matched_header
      else
        # Try fuzzy match (the LLM might return the original header before symbol conversion)
        normalized = csv_header.to_s.downcase.gsub(/\s+/, '_').gsub(/\W+/, '')
        fuzzy = @headers.find { |h| h.downcase.gsub(/\W+/, '') == normalized }
        @mapping[field_sym] = fuzzy if fuzzy
      end
    end
  rescue JSON::ParserError => e
    Rails.logger.warn "📋 CsvColumnMapper: Failed to parse LLM response: #{e.message}"
  end

  def log_mapping(method)
    mapped = @mapping.map { |k, v| "#{k} → '#{v}'" }.join(", ")
    unmapped = @headers - @mapping.values
    Rails.logger.info "📋 CsvColumnMapper (#{method}): Mapped: #{mapped}"
    Rails.logger.info "📋 CsvColumnMapper: Unmapped headers (→ custom_fields): #{unmapped.join(', ')}" if unmapped.any?
  end
end
