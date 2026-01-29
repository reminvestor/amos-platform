# frozen_string_literal: true

# GeminiVisionService - Google Gemini Vision for image understanding and OCR
#
# Uses Gemini 2.0 Flash for fast, accurate image analysis including:
#   - Business card scanning and contact extraction
#   - Document OCR
#   - Image understanding and description
#
# Pricing: ~$0.075/1M input tokens (very cost-effective for vision tasks)
#
class GeminiVisionService
  include HTTParty
  base_uri "https://generativelanguage.googleapis.com/v1beta"

  # Using Gemini 2.0 Flash for best speed/quality balance
  MODEL = "gemini-2.0-flash"

  class VisionError < StandardError; end
  class RateLimitError < StandardError; end

  def initialize
    @api_key = ENV["GEMINI_API_KEY"]
    raise ArgumentError, "GEMINI_API_KEY environment variable not set" if @api_key.blank?
  end

  # Analyze an image with a text prompt
  #
  # @param image_data [String] Base64-encoded image data or file path
  # @param prompt [String] Question or instruction about the image
  # @param mime_type [String] Image MIME type (default: image/jpeg)
  # @return [String] Text response from Gemini
  #
  def analyze(image_data, prompt, mime_type: "image/jpeg")
    # Load image if path provided
    if File.exist?(image_data.to_s)
      mime_type = detect_mime_type(image_data)
      image_data = Base64.strict_encode64(File.binread(image_data))
    end

    response = self.class.post(
      "/models/#{MODEL}:generateContent",
      query: { key: @api_key },
      headers: { "Content-Type" => "application/json" },
      body: build_request_body(image_data, prompt, mime_type).to_json
    )

    handle_response(response)
  end

  # Extract contact information from a business card image
  #
  # @param image_data [String] Base64-encoded image or file path
  # @param mime_type [String] Image MIME type
  # @return [Hash] Parsed contact information
  #
  def extract_business_card(image_data, mime_type: "image/jpeg")
    prompt = <<~PROMPT
      Extract all contact information from this business card image.
      Return ONLY valid JSON with no markdown formatting, no code blocks, just the raw JSON object.

      Use this exact structure (use null for missing fields):
      {
        "name": "Full Name",
        "first_name": "First",
        "last_name": "Last",
        "title": "Job Title",
        "company": "Company Name",
        "email": "email@example.com",
        "phone": "+1-555-123-4567",
        "mobile": "+1-555-987-6543",
        "website": "https://example.com",
        "address": "123 Main St, City, State ZIP",
        "linkedin": "linkedin.com/in/username",
        "twitter": "@username",
        "notes": "Any other relevant info on the card"
      }
    PROMPT

    response_text = analyze(image_data, prompt, mime_type: mime_type)
    parse_json_response(response_text)
  end

  # Extract receipt/expense information
  #
  # @param image_data [String] Base64-encoded image or file path
  # @param mime_type [String] Image MIME type
  # @return [Hash] Parsed receipt information
  #
  def extract_receipt(image_data, mime_type: "image/jpeg")
    prompt = <<~PROMPT
      Extract expense information from this receipt image.
      Return ONLY valid JSON with no markdown formatting, no code blocks, just the raw JSON object.

      Use this exact structure (use null for missing fields):
      {
        "merchant": "Store/Business Name",
        "date": "2024-01-15",
        "total": "$45.99",
        "subtotal": "$42.00",
        "tax": "$3.99",
        "payment_method": "Credit Card",
        "category": "Food & Dining",
        "items": ["Item 1 - $10.00", "Item 2 - $15.00"],
        "notes": "Any additional info"
      }

      Categories should be one of: Food & Dining, Transportation, Office Supplies,
      Travel, Entertainment, Utilities, Healthcare, Other
    PROMPT

    response_text = analyze(image_data, prompt, mime_type: mime_type)
    parse_json_response(response_text)
  end

  # Extract document text with structure
  #
  # @param image_data [String] Base64-encoded image or file path
  # @param mime_type [String] Image MIME type
  # @return [Hash] Extracted document content
  #
  def extract_document(image_data, mime_type: "image/jpeg")
    prompt = <<~PROMPT
      Extract all text and content from this document image.
      Return ONLY valid JSON with no markdown formatting, no code blocks, just the raw JSON object.

      Use this exact structure:
      {
        "title": "Document title if visible",
        "text": "Full extracted text preserving paragraphs",
        "document_type": "letter/form/article/notes/other",
        "key_info": ["Important point 1", "Important point 2"],
        "dates_mentioned": ["2024-01-15"],
        "names_mentioned": ["John Smith"],
        "summary": "Brief 1-2 sentence summary"
      }
    PROMPT

    response_text = analyze(image_data, prompt, mime_type: mime_type)
    parse_json_response(response_text)
  end

  # Extract whiteboard/meeting notes
  #
  # @param image_data [String] Base64-encoded image or file path
  # @param mime_type [String] Image MIME type
  # @return [Hash] Structured meeting notes
  #
  def extract_whiteboard(image_data, mime_type: "image/jpeg")
    prompt = <<~PROMPT
      Extract meeting notes from this whiteboard image.
      Return ONLY valid JSON with no markdown formatting, no code blocks, just the raw JSON object.

      Use this exact structure:
      {
        "title": "Meeting topic if identifiable",
        "text": "Full extracted text from whiteboard",
        "summary": "Brief summary of what's on the whiteboard",
        "key_points": ["Main point 1", "Main point 2", "Main point 3"],
        "action_items": ["Task 1", "Task 2"],
        "diagrams_described": "Description of any diagrams or drawings",
        "participants": ["Names if visible"]
      }

      Focus on extracting actionable information and organizing it clearly.
    PROMPT

    response_text = analyze(image_data, prompt, mime_type: mime_type)
    parse_json_response(response_text)
  end

  # Perform OCR on a document image
  #
  # @param image_data [String] Base64-encoded image or file path
  # @param mime_type [String] Image MIME type
  # @return [String] Extracted text
  #
  def extract_text(image_data, mime_type: "image/jpeg")
    prompt = "Extract all text from this image. Preserve the layout and formatting as much as possible."
    analyze(image_data, prompt, mime_type: mime_type)
  end

  # Describe an image
  #
  # @param image_data [String] Base64-encoded image or file path
  # @param mime_type [String] Image MIME type
  # @return [String] Image description
  #
  def describe(image_data, mime_type: "image/jpeg")
    prompt = "Describe this image in detail. What do you see?"
    analyze(image_data, prompt, mime_type: mime_type)
  end

  private

  def build_request_body(image_data, prompt, mime_type)
    {
      contents: [
        {
          parts: [
            {
              inlineData: {
                mimeType: mime_type,
                data: image_data
              }
            },
            { text: prompt }
          ]
        }
      ],
      generationConfig: {
        temperature: 0.1,  # Low temperature for accurate extraction
        maxOutputTokens: 2048
      }
    }
  end

  def handle_response(response)
    case response.code
    when 200
      parse_text_response(response.parsed_response)
    when 429
      raise RateLimitError, "Gemini API rate limit exceeded"
    else
      error_message = response.dig("error", "message") || response.body
      raise VisionError, "Gemini Vision API error (#{response.code}): #{error_message}"
    end
  end

  def parse_text_response(response)
    candidates = response["candidates"] || []
    content = candidates.dig(0, "content", "parts") || []

    text_part = content.find { |part| part["text"].present? }
    text_part&.dig("text") || ""
  end

  def parse_json_response(text)
    # Clean up the response - remove markdown code blocks if present
    cleaned = text.strip
      .gsub(/^```json\s*/i, "")
      .gsub(/^```\s*/i, "")
      .gsub(/\s*```$/, "")
      .strip

    JSON.parse(cleaned).with_indifferent_access
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse Gemini Vision JSON response: #{e.message}"
    Rails.logger.error "Raw response: #{text}"
    # Return a partial result with the raw text
    { error: "Could not parse response", raw_text: text }
  end

  def detect_mime_type(file_path)
    extension = File.extname(file_path).downcase
    case extension
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".png" then "image/png"
    when ".gif" then "image/gif"
    when ".webp" then "image/webp"
    when ".heic", ".heif" then "image/heic"
    else "image/jpeg"
    end
  end
end
