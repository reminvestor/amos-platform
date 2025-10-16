class SocialMediaAccountsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_account, only: [ :disconnect ]

  # GET /social_media_accounts
  def index
    # Load integrations data similar to canvas
    @integrations = Integration.where(is_active: true).order(:category, :name)
    @connections = current_user.connections.includes(:integration).order(created_at: :desc)
    @social_accounts = current_user.social_media_accounts.order(:platform)
  end

  # GET /social_media_accounts/auth/:platform
  def new
    @platform = params[:platform]

    # Validate platform
    unless SocialMediaAccount::PLATFORMS.include?(@platform)
      redirect_to social_media_accounts_path, alert: "Unsupported platform."
      return
    end

    # Check if already connected
    if current_user.connected_to?(@platform)
      redirect_to social_media_accounts_path, notice: "You are already connected to #{@platform.titleize}."
      return
    end

    # Get OAuth URL
    @oauth_url = get_oauth_url(@platform)
  end

  # GET /social_media_accounts/callback/:platform
  def callback
    @platform = params[:platform]
    code = params[:code]

    # Validate platform
    unless SocialMediaAccount::PLATFORMS.include?(@platform)
      redirect_to social_media_accounts_path, alert: "Unsupported platform."
      return
    end

    # Process OAuth callback
    result = process_oauth_callback(@platform, code)

    if result[:success]
      redirect_to social_media_accounts_path, notice: "Successfully connected to #{@platform.titleize}."
    else
      redirect_to social_media_accounts_path, alert: "Failed to connect: #{result[:error]}"
    end
  end

  # DELETE /social_media_accounts/disconnect/:id
  def disconnect
    platform_name = @account.platform.titleize

    if @account.destroy
      redirect_to social_media_accounts_path, notice: "Successfully disconnected from #{platform_name}."
    else
      redirect_to social_media_accounts_path, alert: "Failed to disconnect from #{platform_name}."
    end
  end

  private

  def set_account
    @account = current_user.social_media_accounts.find(params[:id])
  end

  def get_oauth_url(platform)
    case platform
    when "facebook"
      get_facebook_oauth_url
    when "instagram"
      get_instagram_oauth_url
    when "linkedin"
      get_linkedin_oauth_url
    when "twitter"
      get_twitter_oauth_url
    else
      nil
    end
  end

  def process_oauth_callback(platform, code)
    case platform
    when "facebook"
      process_facebook_callback(code)
    when "instagram"
      process_instagram_callback(code)
    when "linkedin"
      process_linkedin_callback(code)
    when "twitter"
      process_twitter_callback(code)
    else
      { success: false, error: "Unsupported platform" }
    end
  end

  # Facebook OAuth methods
  def get_facebook_oauth_url
    client_id = ENV["FACEBOOK_APP_ID"]
    redirect_uri = callback_social_media_accounts_url(platform: "facebook")
    scope = "public_profile,email,pages_show_list,pages_read_engagement,pages_manage_posts"

    "https://www.facebook.com/v19.0/dialog/oauth" +
    "?client_id=#{client_id}" +
    "&redirect_uri=#{URI.encode_www_form_component(redirect_uri)}" +
    "&scope=#{scope}" +
    "&response_type=code"
  end

  def process_facebook_callback(code)
    client_id = ENV["FACEBOOK_APP_ID"]
    client_secret = ENV["FACEBOOK_APP_SECRET"]
    redirect_uri = callback_social_media_accounts_url(platform: "facebook")

    # Exchange code for access token
    uri = URI("https://graph.facebook.com/v19.0/oauth/access_token")
    response = Net::HTTP.post_form(uri, {
      "client_id" => client_id,
      "client_secret" => client_secret,
      "redirect_uri" => redirect_uri,
      "code" => code
    })

    token_data = JSON.parse(response.body)

    if token_data["access_token"]
      # Get user info
      graph = Koala::Facebook::API.new(token_data["access_token"])
      user_info = graph.get_object("me", fields: "id,name")

      # Create account
      account = current_user.social_media_accounts.create(
        platform: "facebook",
        status: "connected",
        username: user_info["name"],
        profile_url: "https://facebook.com/#{user_info['id']}",
        access_token: token_data["access_token"],
        token_expires_at: Time.now + token_data["expires_in"].to_i.seconds
      )

      { success: true, account: account }
    else
      { success: false, error: token_data["error"]["message"] || "Failed to obtain access token" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  # Instagram OAuth methods
  def get_instagram_oauth_url
    client_id = ENV["INSTAGRAM_CLIENT_ID"]
    redirect_uri = callback_social_media_accounts_url(platform: "instagram")
    scope = "user_profile,user_media"

    "https://api.instagram.com/oauth/authorize" +
    "?client_id=#{client_id}" +
    "&redirect_uri=#{URI.encode_www_form_component(redirect_uri)}" +
    "&scope=#{scope}" +
    "&response_type=code"
  end

  def process_instagram_callback(code)
    client_id = ENV["INSTAGRAM_CLIENT_ID"]
    client_secret = ENV["INSTAGRAM_CLIENT_SECRET"]
    redirect_uri = callback_social_media_accounts_url(platform: "instagram")

    # Exchange code for access token
    uri = URI("https://api.instagram.com/oauth/access_token")
    response = Net::HTTP.post_form(uri, {
      "client_id" => client_id,
      "client_secret" => client_secret,
      "grant_type" => "authorization_code",
      "redirect_uri" => redirect_uri,
      "code" => code
    })

    token_data = JSON.parse(response.body)

    if token_data["access_token"]
      # Get user info
      uri = URI("https://graph.instagram.com/me?fields=id,username&access_token=#{token_data['access_token']}")
      user_info = JSON.parse(Net::HTTP.get(uri))

      # Create account
      account = current_user.social_media_accounts.create(
        platform: "instagram",
        status: "connected",
        username: user_info["username"],
        profile_url: "https://instagram.com/#{user_info['username']}",
        access_token: token_data["access_token"],
        token_expires_at: Time.now + 60.days
      )

      { success: true, account: account }
    else
      { success: false, error: token_data["error_message"] || "Failed to obtain access token" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  # LinkedIn OAuth methods
  def get_linkedin_oauth_url
    client_id = ENV["LINKEDIN_CLIENT_ID"]
    redirect_uri = callback_social_media_accounts_url(platform: "linkedin")
    scope = "r_liteprofile r_emailaddress w_member_social"

    "https://www.linkedin.com/oauth/v2/authorization" +
    "?client_id=#{client_id}" +
    "&redirect_uri=#{URI.encode_www_form_component(redirect_uri)}" +
    "&scope=#{scope}" +
    "&response_type=code"
  end

  def process_linkedin_callback(code)
    client_id = ENV["LINKEDIN_CLIENT_ID"]
    client_secret = ENV["LINKEDIN_CLIENT_SECRET"]
    redirect_uri = callback_social_media_accounts_url(platform: "linkedin")

    # Exchange code for access token
    uri = URI("https://www.linkedin.com/oauth/v2/accessToken")
    response = Net::HTTP.post_form(uri, {
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri,
      "client_id" => client_id,
      "client_secret" => client_secret
    })

    token_data = JSON.parse(response.body)

    if token_data["access_token"]
      # Get user info
      uri = URI("https://api.linkedin.com/v2/me")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token_data['access_token']}"
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      user_info = JSON.parse(response.body)

      # Create account
      account = current_user.social_media_accounts.create(
        platform: "linkedin",
        status: "connected",
        username: "#{user_info['localizedFirstName']} #{user_info['localizedLastName']}",
        profile_url: "https://linkedin.com/in/#{user_info['id']}",
        access_token: token_data["access_token"],
        refresh_token: token_data["refresh_token"],
        token_expires_at: Time.now + token_data["expires_in"].to_i.seconds
      )

      { success: true, account: account }
    else
      { success: false, error: token_data["error_description"] || "Failed to obtain access token" }
    end
  rescue => e
    { success: false, error: e.message }
  end

  # Twitter OAuth methods
  def get_twitter_oauth_url
    client_id = ENV["TWITTER_CLIENT_ID"]
    redirect_uri = callback_social_media_accounts_url(platform: "twitter")
    scope = "tweet.read tweet.write users.read"

    "https://twitter.com/i/oauth2/authorize" +
    "?client_id=#{client_id}" +
    "&redirect_uri=#{URI.encode_www_form_component(redirect_uri)}" +
    "&scope=#{scope}" +
    "&response_type=code" +
    "&code_challenge=challenge" +
    "&code_challenge_method=plain"
  end

  def process_twitter_callback(code)
    client_id = ENV["TWITTER_CLIENT_ID"]
    client_secret = ENV["TWITTER_CLIENT_SECRET"]
    redirect_uri = callback_social_media_accounts_url(platform: "twitter")

    # Exchange code for access token
    uri = URI("https://api.twitter.com/2/oauth2/token")
    auth = "Basic " + Base64.strict_encode64("#{client_id}:#{client_secret}")

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = auth
    request["Content-Type"] = "application/x-www-form-urlencoded"
    request.body = URI.encode_www_form({
      "grant_type" => "authorization_code",
      "code" => code,
      "redirect_uri" => redirect_uri,
      "code_verifier" => "challenge"
    })

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    token_data = JSON.parse(response.body)

    if token_data["access_token"]
      # Get user info
      uri = URI("https://api.twitter.com/2/users/me")
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token_data['access_token']}"
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
      user_info = JSON.parse(response.body)

      # Create account
      account = current_user.social_media_accounts.create(
        platform: "twitter",
        status: "connected",
        username: user_info["data"]["username"],
        profile_url: "https://twitter.com/#{user_info['data']['username']}",
        access_token: token_data["access_token"],
        refresh_token: token_data["refresh_token"],
        token_expires_at: Time.now + token_data["expires_in"].to_i.seconds
      )

      { success: true, account: account }
    else
      { success: false, error: token_data["error_description"] || "Failed to obtain access token" }
    end
  rescue => e
    { success: false, error: e.message }
  end
end
