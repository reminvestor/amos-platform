require 'faraday'
require 'base64'

module AiAgents::Mcp
  class JiraClient
    attr_reader :connection

    # JIRA Cloud API v3 endpoints
    API_VERSION = '/rest/api/3'

    def initialize(connection)
      @connection = connection
      @config = connection.config
      @base_url = @config['api_url'] || @config[:api_url] || @config['url'] || @config[:url]
      @email = @config['email'] || @config[:email]
      @api_token = @config['api_token'] || @config[:api_token]
      @project_key = @config['project_key'] || @config[:project_key]

      raise "JIRA URL not configured" unless @base_url
      raise "JIRA email not configured" unless @email
      raise "JIRA API token not configured" unless @api_token
    end

    # Test connection by fetching current user
    def test_connection
      response = http_client.get("#{API_VERSION}/myself")

      if response.success?
        user_data = JSON.parse(response.body)
        {
          success: true,
          message: "Connected to JIRA as #{user_data['displayName']}",
          data: {
            user: user_data['displayName'],
            email: user_data['emailAddress'],
            account_id: user_data['accountId']
          }
        }
      else
        {
          success: false,
          error: "JIRA connection failed: #{response.status} - #{response.body}"
        }
      end
    rescue => e
      {
        success: false,
        error: "JIRA connection error: #{e.message}"
      }
    end

    # Fetch recent tickets using JQL query
    def fetch_recent_tickets(since: 10.minutes.ago)
      # Build JQL query
      jql = build_jql_query(since)

      # Make API request
      response = http_client.get("#{API_VERSION}/search") do |req|
        req.params['jql'] = jql
        req.params['fields'] = 'summary,description,status,priority,labels,issuetype,assignee,components,customfield_*'
        req.params['maxResults'] = 50
      end

      unless response.success?
        Rails.logger.error "JIRA API error: #{response.status} - #{response.body}"
        return []
      end

      data = JSON.parse(response.body)
      issues = data['issues'] || []

      # Normalize to standard ticket format
      issues.map { |issue| normalize_ticket(issue) }
    rescue => e
      Rails.logger.error "JIRA fetch error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      []
    end

    # Post comment to a JIRA issue
    def add_comment(ticket_id, comment)
      response = http_client.post("#{API_VERSION}/issue/#{ticket_id}/comment") do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          body: {
            type: 'doc',
            version: 1,
            content: [
              {
                type: 'paragraph',
                content: [
                  {
                    type: 'text',
                    text: comment
                  }
                ]
              }
            ]
          }
        }.to_json
      end

      if response.success?
        { success: true, message: "Comment posted to #{ticket_id}" }
      else
        {
          success: false,
          error: "Failed to post comment: #{response.status} - #{response.body}"
        }
      end
    rescue => e
      {
        success: false,
        error: "Comment posting error: #{e.message}"
      }
    end

    # Transition issue to new status
    def transition_ticket(ticket_id, state)
      # Get available transitions
      transitions_response = http_client.get("#{API_VERSION}/issue/#{ticket_id}/transitions")
      return { success: false, error: "Failed to get transitions" } unless transitions_response.success?

      transitions_data = JSON.parse(transitions_response.body)
      transitions = transitions_data['transitions'] || []

      # Find matching transition
      transition = transitions.find { |t| t['name'].downcase == state.downcase }

      unless transition
        return {
          success: false,
          error: "Transition '#{state}' not found. Available: #{transitions.map { |t| t['name'] }.join(', ')}"
        }
      end

      # Execute transition
      response = http_client.post("#{API_VERSION}/issue/#{ticket_id}/transitions") do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          transition: { id: transition['id'] }
        }.to_json
      end

      if response.success?
        { success: true, message: "Issue transitioned to #{state}" }
      else
        {
          success: false,
          error: "Transition failed: #{response.status} - #{response.body}"
        }
      end
    rescue => e
      {
        success: false,
        error: "Transition error: #{e.message}"
      }
    end

    # Attach file to JIRA issue
    def attach_file(ticket_id, file_path, filename)
      File.open(file_path, 'rb') do |file|
        response = http_client.post("#{API_VERSION}/issue/#{ticket_id}/attachments") do |req|
          req.headers['X-Atlassian-Token'] = 'no-check'
          req.headers['Content-Type'] = 'multipart/form-data'
          req.body = {
            file: Faraday::UploadIO.new(file, 'application/octet-stream', filename)
          }
        end

        if response.success?
          { success: true, message: "File attached to #{ticket_id}" }
        else
          {
            success: false,
            error: "Failed to attach file: #{response.status} - #{response.body}"
          }
        end
      end
    rescue => e
      {
        success: false,
        error: "File attachment error: #{e.message}"
      }
    end

    private

    # Build HTTP client with authentication
    def http_client
      @http_client ||= Faraday.new(url: @base_url) do |f|
        f.request :authorization, :basic, @email, @api_token
        f.adapter Faraday.default_adapter
        f.options.timeout = 30
        f.options.open_timeout = 10
      end
    end

    # Build JQL query for fetching recent tickets
    def build_jql_query(since)
      # Convert time to JIRA format (minutes ago)
      minutes_ago = ((Time.current - since) / 60).to_i

      jql_parts = []

      # Project filter
      if @project_key
        jql_parts << "project = #{@project_key}"
      end

      # Time filter (created or updated recently)
      jql_parts << "(created >= -#{minutes_ago}m OR updated >= -#{minutes_ago}m)"

      # Order by created date descending
      jql = jql_parts.join(' AND ')
      jql += ' ORDER BY created DESC'

      jql
    end

    # Normalize JIRA issue to standard ticket format
    def normalize_ticket(jira_issue)
      fields = jira_issue['fields']

      {
        id: jira_issue['key'],
        title: fields['summary'],
        description: extract_description(fields['description']),
        url: "#{@base_url}/browse/#{jira_issue['key']}",
        status: fields['status']&.dig('name'),
        labels: fields['labels'] || [],
        issue_type: fields['issuetype']&.dig('name'),
        assignee: fields['assignee']&.dig('displayName'),
        priority: fields['priority']&.dig('name') || 'medium',
        components: (fields['components'] || []).map { |c| c['name'] },
        custom_fields: extract_custom_fields(fields),
        metadata: {
          story_points: fields['customfield_10016'], # Common story points field
          epic_link: fields['customfield_10014'],     # Common epic link field
          sprint: fields['customfield_10020'],        # Common sprint field
          reporter: fields['reporter']&.dig('displayName'),
          created_at: fields['created'],
          updated_at: fields['updated']
        }
      }
    end

    # Extract description text from JIRA's Atlassian Document Format (ADF)
    def extract_description(description)
      return '' if description.nil?

      # JIRA Cloud uses ADF (Atlassian Document Format)
      if description.is_a?(Hash) && description['type'] == 'doc'
        extract_text_from_adf(description)
      elsif description.is_a?(String)
        description
      else
        description.to_s
      end
    end

    # Extract plain text from Atlassian Document Format
    def extract_text_from_adf(adf_doc)
      return '' unless adf_doc['content']

      adf_doc['content'].map do |block|
        extract_text_from_adf_block(block)
      end.join("\n\n")
    end

    def extract_text_from_adf_block(block)
      case block['type']
      when 'paragraph', 'heading'
        (block['content'] || []).map do |inline|
          inline['text'] || extract_text_from_adf_block(inline)
        end.join
      when 'bulletList', 'orderedList'
        (block['content'] || []).map do |item|
          "- #{extract_text_from_adf_block(item)}"
        end.join("\n")
      when 'listItem'
        (block['content'] || []).map do |content|
          extract_text_from_adf_block(content)
        end.join(' ')
      when 'codeBlock'
        "```\n#{block['content']&.first&.dig('text')}\n```"
      when 'text'
        block['text']
      else
        (block['content'] || []).map do |content|
          extract_text_from_adf_block(content)
        end.join(' ')
      end
    end

    # Extract custom fields from JIRA issue
    def extract_custom_fields(fields)
      custom = {}

      fields.each do |key, value|
        next unless key.start_with?('customfield_')
        next if value.nil?

        # Convert customfield_10016 to readable name if possible
        field_name = key.sub('customfield_', 'custom_')
        custom[field_name] = value
      end

      custom
    end
  end
end
