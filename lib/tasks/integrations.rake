namespace :integrations do
  desc "Seed example integrations (Stripe, Shopify, HubSpot, etc.)"
  task seed: :environment do
    require_relative "../../db/seeds/integrations"
  end

  desc "Add a custom integration via interactive prompts"
  task add_custom: :environment do
    puts "\n🔌 Custom Integration Setup Wizard\n\n"

    # Basic Information
    print "Integration name (e.g., 'My CRM'): "
    name = STDIN.gets.chomp

    print "Slug (e.g., 'my_crm'): "
    slug = STDIN.gets.chomp.downcase.gsub(/\s+/, "_")

    print "Category (payment/ecommerce/crm/communication/productivity/analytics/custom): "
    category = STDIN.gets.chomp

    print "Description: "
    description = STDIN.gets.chomp

    print "API Base URL (e.g., 'https://api.mycrm.com/v2'): "
    api_base_url = STDIN.gets.chomp

    print "Documentation URL (optional): "
    documentation_url = STDIN.gets.chomp

    # Authentication
    puts "\nAuthentication Setup:"
    puts "1. API Key (header or query parameter)"
    puts "2. Bearer Token"
    puts "3. Basic Auth (username/password)"
    puts "4. OAuth2 (you have registered app)"
    puts "5. OAuth2 Custom (user registers their own app)"
    print "\nSelect auth type (1-5): "

    auth_choice = STDIN.gets.chomp.to_i
    auth_type = case auth_choice
    when 1 then "api_key"
    when 2 then "bearer_token"
    when 3 then "basic_auth"
    when 4 then "oauth2"
    when 5 then "oauth2_custom"
    else "api_key"
    end

    auth_config = {}
    case auth_type
    when "api_key"
      print "Where is the API key sent? (header/query): "
      auth_method = STDIN.gets.chomp
      auth_config[:auth_method] = auth_method

      if auth_method == "header"
        print "Header name (e.g., 'X-API-Key'): "
        auth_config[:auth_field_name] = STDIN.gets.chomp
      else
        print "Query parameter name (e.g., 'api_key'): "
        auth_config[:auth_field_name] = STDIN.gets.chomp
      end

    when "bearer_token"
      auth_config[:auth_method] = "bearer"
      auth_config[:auth_field_name] = "Authorization"
      auth_config[:auth_prefix] = "Bearer"

    when "basic_auth"
      auth_config[:auth_method] = "basic"

    when "oauth2", "oauth2_custom"
      print "OAuth2 Authorization URL: "
      auth_config[:authorize_url] = STDIN.gets.chomp

      print "OAuth2 Token URL: "
      auth_config[:token_url] = STDIN.gets.chomp

      print "Required scopes (comma-separated): "
      auth_config[:scopes] = STDIN.gets.chomp.split(",").map(&:strip)
    end

    print "\nSetup instructions for users: "
    auth_config[:setup_instructions] = STDIN.gets.chomp

    # Create the integration
    integration = Integration.create!(
      name: name,
      slug: slug,
      category: category,
      description: description,
      auth_type: auth_type,
      api_base_url: api_base_url,
      allowed_hosts: [ URI.parse(api_base_url).host ],
      documentation_url: documentation_url.presence,
      is_active: true,
      is_verified: false,
      auth_config: auth_config,
      metadata: {}
    )

    puts "\n✅ Integration created!"

    # Add operations
    print "\nWould you like to add API operations now? (y/n): "
    if STDIN.gets.chomp.downcase == "y"
      loop do
        puts "\n📝 Add Operation:"

        print "Operation name (e.g., 'List Users'): "
        op_name = STDIN.gets.chomp

        print "Operation ID (e.g., 'my_crm.list_users.v1'): "
        operation_id = STDIN.gets.chomp

        print "HTTP method (GET/POST/PUT/PATCH/DELETE): "
        http_method = STDIN.gets.chomp.upcase

        print "Path template (e.g., '/api/users' or '/api/users/{id}'): "
        path_template = STDIN.gets.chomp

        print "Description: "
        op_description = STDIN.gets.chomp

        print "Requires confirmation? (y/n): "
        requires_confirmation = STDIN.gets.chomp.downcase == "y"

        # Create the operation
        integration.integration_operations.create!(
          operation_id: operation_id,
          name: op_name,
          description: op_description,
          http_method: http_method,
          path_template: path_template,
          pagination_strategy: "none",
          is_idempotent: http_method == "GET",
          requires_confirmation: requires_confirmation,
          request_schema: {},
          response_schema: {}
        )

        puts "✅ Operation added!"

        print "\nAdd another operation? (y/n): "
        break unless STDIN.gets.chomp.downcase == "y"
      end
    end

    puts "\n🎉 Custom integration '#{name}' is ready to use!"
    puts "\nUsers can now:"
    puts "1. Go to Settings > Integrations"
    puts "2. Find '#{name}' and click 'Connect'"
    puts "3. Follow the setup instructions to add their credentials"
    puts "4. Start using it with Scout AI!"
  end

  desc "List all integrations and their operations"
  task list: :environment do
    Integration.includes(:integration_operations).each do |integration|
      puts "\n#{integration.name} (#{integration.slug})"
      puts "  Category: #{integration.category}"
      puts "  Auth Type: #{integration.auth_type}"
      puts "  Status: #{integration.is_active ? 'Active' : 'Inactive'}"
      puts "  Operations:"

      integration.integration_operations.each do |op|
        puts "    - #{op.name} (#{op.operation_id})"
        puts "      #{op.http_method} #{op.path_template}"
      end
    end
  end

  desc "Export an integration as JSON (for sharing)"
  task :export, [ :slug ] => :environment do |t, args|
    integration = Integration.find_by!(slug: args[:slug])

    export_data = {
      integration: integration.attributes.except("id", "created_at", "updated_at"),
      operations: integration.integration_operations.map do |op|
        op.attributes.except("id", "integration_id", "created_at", "updated_at")
      end
    }

    filename = "#{integration.slug}_integration.json"
    File.write(filename, JSON.pretty_generate(export_data))

    puts "✅ Exported to #{filename}"
  end

  desc "Import an integration from JSON"
  task :import, [ :filename ] => :environment do |t, args|
    data = JSON.parse(File.read(args[:filename]))

    # Create or update integration
    integration = Integration.find_or_initialize_by(slug: data["integration"]["slug"])
    integration.assign_attributes(data["integration"])
    integration.save!

    # Create or update operations
    data["operations"].each do |op_data|
      operation = integration.integration_operations
                            .find_or_initialize_by(operation_id: op_data["operation_id"])
      operation.assign_attributes(op_data)
      operation.save!
    end

    puts "✅ Imported #{integration.name} with #{data['operations'].length} operations"
  end
end
