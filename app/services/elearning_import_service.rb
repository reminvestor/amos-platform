class ElearningImportService
  attr_reader :stats

  def initialize(options = {})
    @base_url = options[:base_url] || ENV["ELEARNING_API_URL"] || "http://localhost:3000"
    @api_key = options[:api_key] || ENV["ELEARNING_API_KEY"]
    @per_page = options[:per_page] || 100
    @admin_user = options[:admin_user] || User.find_by(admin: true) || User.first

    raise "No admin user found" unless @admin_user
    raise "API key is required" unless @api_key

    @stats = {
      total_imported: 0,
      subscribers_count: 0,
      non_subscribers_count: 0,
      errors: 0
    }
  end

  def import_users(options = {})
    create_contact_groups

    page = 1
    total_pages = 1

    while page <= total_pages
      puts "Processing page #{page} of #{total_pages}..."

      begin
        response = fetch_users_page(page)
        data = JSON.parse(response.body)
        total_pages = data["total_pages"]

        process_users_batch(data["users"])
      rescue => e
        @stats[:errors] += 1
        puts "Error on page #{page}: #{e.message}"
      end

      page += 1
    end

    puts "Import completed!"
    puts "Total contacts imported: #{@stats[:total_imported]}"
    puts "Active subscribers: #{@stats[:subscribers_count]}"
    puts "Non-subscribers: #{@stats[:non_subscribers_count]}"
    puts "Errors: #{@stats[:errors]}"

    @stats
  end

  private

  def create_contact_groups
    @subscriber_group = ContactGroup.find_or_create_by(
      user: @admin_user,
      name: "Active Subscribers"
    )

    @non_subscriber_group = ContactGroup.find_or_create_by(
      user: @admin_user,
      name: "Non-Subscribers"
    )
  end

  def fetch_users_page(page)
    uri = URI("#{@base_url}/api/v1/users/subscribers?page=#{page}&per_page=#{@per_page}")
    request = Net::HTTP::Get.new(uri)
    request["X-API-Key"] = @api_key

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(request)
    end

    if response.code != "200"
      raise "API error: #{response.code} - #{response.body}"
    end

    response
  end

  def process_users_batch(users)
    users.each do |user_data|
      process_user(user_data)
    end
  end

  def process_user(user_data)
    # Create or update contact
    contact = Contact.find_or_initialize_by(
      email: user_data["email"],
      user: @admin_user
    )

    result = contact.update(
      first_name: user_data["name"],
      last_name: user_data["last_name"],
      status: "active",
      metadata: {
        corporation_id: user_data["corporation_id"],
        corporation_name: user_data["corporation_name"],
        imported_at: Time.current
      }
    )

    if result
      # Add to appropriate group
      if user_data["active_subscriber"]
        contact.contact_groups << @subscriber_group unless contact.contact_groups.include?(@subscriber_group)
        @stats[:subscribers_count] += 1
      else
        contact.contact_groups << @non_subscriber_group unless contact.contact_groups.include?(@non_subscriber_group)
        @stats[:non_subscribers_count] += 1
      end

      @stats[:total_imported] += 1
    else
      @stats[:errors] += 1
      puts "Error importing contact: #{contact.errors.full_messages.join(', ')}"
    end
  end
end
