# db/seeds/tool_definitions.rb

puts "🛠️  Seeding Tool Definitions..."

def seed_tool(name, attributes)
  tool = ToolDefinition.find_or_initialize_by(name: name)
  
  # Preserve ID if it exists to avoid breaking associations, but update attributes
  tool.assign_attributes(attributes)
  
  # Force admin_only to false for seeded tools so they are public/usable
  tool.admin_only = false
  tool.is_public = true
  tool.published_at = Time.current if tool.published_at.nil?
  
  # Try to save. If validation fails (security check), log it but don't crash seeds
  if tool.save
    puts "  ✓ Created/Updated Tool: #{name}"
  else
    # If failed due to security, try to save as 'review' if possible, or just log
    if tool.errors[:base].any? { |e| e.include?("Security Audit Failed") }
       puts "  ⚠️  Tool #{name} flagged by Security Audit: #{tool.security_reason}"
       # We could force save with 'review' status if we trust our seeds, 
       # but let's respect the system. I'll just let it fail and we can see.
       # Actually, for seeds, we might want to bypass if we trust the code.
       # But for now, let's test the system.
    else
       puts "  x Failed to seed Tool #{name}: #{tool.errors.full_messages.join(', ')}"
    end
  end
end

# 1. Loan Payment Calculator (Ruby)
seed_tool("calculate_loan_payment", {
  description: "Calculates the monthly payment for a loan based on principal, interest rate, and term.",
  execution_type: "ruby_code",
  parameters: {
    type: "object",
    properties: {
      principal: { type: "number", description: "Loan amount" },
      annual_rate: { type: "number", description: "Annual interest rate in percent (e.g. 5.0)" },
      years: { type: "number", description: "Loan term in years" }
    },
    required: ["principal", "annual_rate", "years"]
  },
  code: <<~RUBY
    principal = args['principal'].to_f
    rate = args['annual_rate'].to_f / 100.0 / 12.0
    months = args['years'].to_f * 12.0

    if rate == 0
      payment = principal / months
    else
      payment = principal * (rate * (1 + rate)**months) / ((1 + rate)**months - 1)
    end

    {
      monthly_payment: payment.round(2),
      total_payment: (payment * months).round(2),
      total_interest: ((payment * months) - principal).round(2)
    }
  RUBY
})

# 2. CSV to JSON Parser (Ruby)
seed_tool("parse_csv_data", {
  description: "Parses a CSV string into a JSON array of objects.",
  execution_type: "ruby_code",
  parameters: {
    type: "object",
    properties: {
      csv_content: { type: "string", description: "Raw CSV string" },
      has_headers: { type: "boolean", default: true, description: "Whether the first row is headers" }
    },
    required: ["csv_content"]
  },
  code: <<~RUBY
    require 'csv'
    
    content = args['csv_content']
    has_headers = args['has_headers'] != false
    
    begin
      data = CSV.parse(content, headers: has_headers)
      if has_headers
        # Convert to array of hashes
        data.map(&:to_h)
      else
        # Convert to array of arrays
        data
      end
    rescue => e
      { error: "Failed to parse CSV: \#{e.message}" }
    end
  RUBY
})

# 3. Current Weather (OpenMeteo)
seed_tool("get_current_weather", {
  description: "Get current weather for a location (latitude/longitude).",
  execution_type: "http_request",
  parameters: {
    type: "object",
    properties: {
      latitude: { type: "number", description: "Latitude" },
      longitude: { type: "number", description: "Longitude" }
    },
    required: ["latitude", "longitude"]
  },
  api_config: {
    url: "https://api.open-meteo.com/v1/forecast?latitude={{latitude}}&longitude={{longitude}}&current_weather=true",
    method: "GET"
  }
})

# NOTE: Class-based tools like load_design_canvas, generate_automation_code, etc.
# are registered via ToolRegistry and don't need to be in the ToolDefinition table.
# They are loaded automatically from the Tools:: namespace.

puts "✅ Tool Definitions seeded."

