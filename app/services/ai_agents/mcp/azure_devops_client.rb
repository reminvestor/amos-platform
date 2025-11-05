require 'faraday'
require 'base64'

module AiAgents::Mcp
  class AzureDevopsClient
    attr_reader :connection

    # Azure DevOps REST API v7.0 endpoints
    API_VERSION = '7.0'

    def initialize(connection)
      @connection = connection
      @config = connection.config
      @organization = @config['organization'] || @config[:organization]
      @project = @config['project'] || @config[:project]
      @api_token = @config['api_token'] || @config[:api_token]

      raise "Azure DevOps organization not configured" unless @organization
      raise "Azure DevOps project not configured" unless @project
      raise "Azure DevOps API token not configured" unless @api_token

      @base_url = "https://dev.azure.com/#{@organization}"
    end

    # Test connection by fetching current user profile
    def test_connection
      response = http_client.get("https://app.vssps.visualstudio.com/_apis/profile/profiles/me") do |req|
        req.params['api-version'] = API_VERSION
      end

      if response.success?
        profile_data = JSON.parse(response.body)
        {
          success: true,
          message: "Connected to Azure DevOps as #{profile_data['displayName']}",
          data: {
            user: profile_data['displayName'],
            email: profile_data['emailAddress'],
            id: profile_data['id']
          }
        }
      else
        {
          success: false,
          error: "Azure DevOps connection failed: #{response.status} - #{response.body}"
        }
      end
    rescue => e
      {
        success: false,
        error: "Azure DevOps connection error: #{e.message}"
      }
    end

    # Fetch recent work items using WIQL (Work Item Query Language)
    def fetch_recent_tickets(since: 10.minutes.ago)
      # Build WIQL query
      wiql = build_wiql_query(since)

      # Execute WIQL query to get work item IDs
      response = http_client.post("#{@base_url}/#{@project}/_apis/wit/wiql") do |req|
        req.params['api-version'] = API_VERSION
        req.headers['Content-Type'] = 'application/json'
        req.body = { query: wiql }.to_json
      end

      unless response.success?
        Rails.logger.error "Azure DevOps WIQL error: #{response.status} - #{response.body}"
        return []
      end

      query_result = JSON.parse(response.body)
      work_item_ids = query_result['workItems']&.map { |wi| wi['id'] } || []

      return [] if work_item_ids.empty?

      # Fetch full work item details in batch
      fetch_work_items(work_item_ids)
    rescue => e
      Rails.logger.error "Azure DevOps fetch error: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      []
    end

    # Post comment to a work item
    def add_comment(ticket_id, comment)
      response = http_client.post("#{@base_url}/#{@project}/_apis/wit/workItems/#{ticket_id}/comments") do |req|
        req.params['api-version'] = API_VERSION
        req.headers['Content-Type'] = 'application/json'
        req.body = {
          text: comment
        }.to_json
      end

      if response.success?
        { success: true, message: "Comment posted to work item #{ticket_id}" }
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

    # Transition work item to new state
    def transition_ticket(ticket_id, state)
      # Azure DevOps uses PATCH with JSON Patch format
      response = http_client.patch("#{@base_url}/#{@project}/_apis/wit/workItems/#{ticket_id}") do |req|
        req.params['api-version'] = API_VERSION
        req.headers['Content-Type'] = 'application/json-patch+json'
        req.body = [
          {
            op: 'add',
            path: '/fields/System.State',
            value: state
          }
        ].to_json
      end

      if response.success?
        { success: true, message: "Work item transitioned to #{state}" }
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

    # Attach file to work item
    def attach_file(ticket_id, file_path, filename)
      # Step 1: Upload file to attachment store
      File.open(file_path, 'rb') do |file|
        upload_response = http_client.post("#{@base_url}/#{@project}/_apis/wit/attachments") do |req|
          req.params['api-version'] = API_VERSION
          req.params['fileName'] = filename
          req.headers['Content-Type'] = 'application/octet-stream'
          req.body = file.read
        end

        unless upload_response.success?
          return {
            success: false,
            error: "Failed to upload attachment: #{upload_response.status} - #{upload_response.body}"
          }
        end

        attachment_data = JSON.parse(upload_response.body)
        attachment_url = attachment_data['url']

        # Step 2: Link attachment to work item
        link_response = http_client.patch("#{@base_url}/#{@project}/_apis/wit/workItems/#{ticket_id}") do |req|
          req.params['api-version'] = API_VERSION
          req.headers['Content-Type'] = 'application/json-patch+json'
          req.body = [
            {
              op: 'add',
              path: '/relations/-',
              value: {
                rel: 'AttachedFile',
                url: attachment_url,
                attributes: {
                  comment: "Uploaded by AI Pipeline"
                }
              }
            }
          ].to_json
        end

        if link_response.success?
          { success: true, message: "File attached to work item #{ticket_id}" }
        else
          {
            success: false,
            error: "Failed to link attachment: #{link_response.status} - #{link_response.body}"
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

    # Build HTTP client with Personal Access Token authentication
    def http_client
      @http_client ||= Faraday.new do |f|
        # Azure DevOps uses Basic Auth with empty username and PAT as password
        f.request :authorization, :basic, '', @api_token
        f.adapter Faraday.default_adapter
        f.options.timeout = 30
        f.options.open_timeout = 10
      end
    end

    # Build WIQL query for fetching recent work items
    def build_wiql_query(since)
      # Convert time to ISO format for Azure DevOps
      since_time = since.iso8601

      wiql_parts = []

      # Project filter
      wiql_parts << "[System.TeamProject] = '#{@project}'"

      # Work item type filter (exclude test cases, test suites)
      wiql_parts << "[System.WorkItemType] NOT IN ('Test Case', 'Test Suite', 'Test Plan')"

      # Time filter (created or changed recently)
      wiql_parts << "([System.CreatedDate] >= '#{since_time}' OR [System.ChangedDate] >= '#{since_time}')"

      # Build query
      wiql = "SELECT [System.Id] FROM WorkItems WHERE #{wiql_parts.join(' AND ')} ORDER BY [System.CreatedDate] DESC"

      wiql
    end

    # Fetch full work item details by IDs
    def fetch_work_items(work_item_ids)
      # Azure DevOps allows fetching up to 200 work items per request
      ids = work_item_ids.first(200).join(',')

      response = http_client.get("#{@base_url}/#{@project}/_apis/wit/workitems") do |req|
        req.params['ids'] = ids
        req.params['api-version'] = API_VERSION
        req.params['$expand'] = 'all'
      end

      unless response.success?
        Rails.logger.error "Azure DevOps work items fetch error: #{response.status} - #{response.body}"
        return []
      end

      data = JSON.parse(response.body)
      work_items = data['value'] || []

      # Normalize to standard ticket format
      work_items.map { |wi| normalize_ticket(wi) }
    rescue => e
      Rails.logger.error "Azure DevOps work items fetch error: #{e.message}"
      []
    end

    # Normalize Azure DevOps work item to standard ticket format
    def normalize_ticket(work_item)
      fields = work_item['fields']

      {
        id: work_item['id'].to_s,
        title: fields['System.Title'],
        description: fields['System.Description'] || '',
        url: work_item['_links']&.dig('html', 'href') || "#{@base_url}/#{@project}/_workitems/edit/#{work_item['id']}",
        status: fields['System.State'],
        labels: (fields['System.Tags'] || '').split(';').map(&:strip).reject(&:empty?),
        issue_type: fields['System.WorkItemType'],
        assignee: fields['System.AssignedTo']&.dig('displayName'),
        priority: map_priority(fields['Microsoft.VSTS.Common.Priority']),
        components: [fields['System.AreaPath']].compact,
        custom_fields: extract_custom_fields(fields),
        metadata: {
          story_points: fields['Microsoft.VSTS.Scheduling.StoryPoints'],
          iteration_path: fields['System.IterationPath'],
          reason: fields['System.Reason'],
          created_by: fields['System.CreatedBy']&.dig('displayName'),
          created_at: fields['System.CreatedDate'],
          updated_at: fields['System.ChangedDate'],
          parent_id: fields['System.Parent'],
          board_column: fields['System.BoardColumn'],
          board_column_done: fields['System.BoardColumnDone']
        }
      }
    end

    # Map Azure DevOps priority (1-4) to standard priority (critical, high, medium, low)
    def map_priority(ado_priority)
      case ado_priority
      when 1
        'critical'
      when 2
        'high'
      when 3
        'medium'
      when 4, nil
        'low'
      else
        'medium'
      end
    end

    # Extract custom fields from work item
    def extract_custom_fields(fields)
      custom = {}

      # Extract common custom fields
      custom_field_mappings = {
        'Microsoft.VSTS.Common.AcceptanceCriteria' => 'acceptance_criteria',
        'Microsoft.VSTS.Common.Risk' => 'risk',
        'Microsoft.VSTS.Common.TargetDate' => 'target_date',
        'Microsoft.VSTS.Scheduling.Effort' => 'effort',
        'Microsoft.VSTS.Scheduling.RemainingWork' => 'remaining_work',
        'Microsoft.VSTS.Scheduling.CompletedWork' => 'completed_work',
        'Microsoft.VSTS.Build.IntegrationBuild' => 'integration_build'
      }

      custom_field_mappings.each do |ado_field, custom_name|
        value = fields[ado_field]
        custom[custom_name] = value if value
      end

      # Extract any other custom fields (Custom.* namespace)
      fields.each do |key, value|
        next unless key.start_with?('Custom.')
        next if value.nil?

        field_name = key.sub('Custom.', '').underscore
        custom[field_name] = value
      end

      custom
    end
  end
end
