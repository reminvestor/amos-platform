module Git
  class GithubClient
    attr_reader :connection

    def initialize(connection)
      @connection = connection
      @config = connection.config
      @mcp = MCP::Manager.instance
    end

    # Test connection by searching for organization repositories
    def test_connection
      begin
        result = call_mcp_tool('search_repositories', {
          query: "org:#{@config[:organization]}"
        })

        if result[:success]
          repos_count = result[:content].is_a?(Array) ? result[:content].length : 0
          {
            success: true,
            message: "Connected to GitHub organization: #{@config[:organization]}",
            data: {
              organization: @config[:organization],
              repo_count: repos_count
            }
          }
        else
          { success: false, error: result[:error] || 'Connection test failed' }
        end
      rescue => e
        { success: false, error: "GitHub API error: #{e.message}" }
      end
    end

    # List repositories in the organization
    def list_repositories
      begin
        result = call_mcp_tool('search_repositories', {
          query: "org:#{@config[:organization]}"
        })

        if result[:success]
          repositories = parse_repositories(result[:content])
          {
            success: true,
            repositories: repositories
          }
        else
          { success: false, error: result[:error] || 'Failed to list repositories' }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Get repository information
    def get_repository(repo_full_name)
      begin
        # Use get_file_contents with empty path to get repo info
        result = call_mcp_tool('search_repositories', {
          query: "repo:#{repo_full_name}"
        })

        if result[:success] && result[:content].is_a?(Array) && result[:content].any?
          repo_data = result[:content].first
          {
            success: true,
            repository: {
              name: repo_data['name'],
              full_name: repo_data['full_name'] || repo_full_name,
              default_branch: repo_data['default_branch'] || 'main',
              clone_url: repo_data['clone_url'],
              ssh_url: repo_data['ssh_url']
            }
          }
        else
          { success: false, error: 'Repository not found' }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Create a pull request
    def create_pull_request(repo_full_name, options)
      begin
        # Options: { title:, body:, head: (branch), base: (target branch) }
        result = call_mcp_tool('create_pull_request', {
          owner: repo_full_name.split('/').first,
          repo: repo_full_name.split('/').last,
          title: options[:title],
          body: options[:body] || '',
          head: options[:head],
          base: options[:base] || 'main'
        })

        if result[:success]
          pr_data = parse_pr_response(result[:content])
          {
            success: true,
            pr_url: pr_data[:html_url],
            pr_id: pr_data[:number].to_s,
            pr_number: pr_data[:number],
            state: pr_data[:state]
          }
        else
          { success: false, error: result[:error] || 'Failed to create PR' }
        end
      rescue => e
        { success: false, error: "GitHub API error: #{e.message}" }
      end
    end

    # Get pull request details and files
    def get_pull_request(repo_full_name, pr_number)
      begin
        # MCP GitHub server doesn't have a direct get_pr method
        # We'll need to use the GitHub API through MCP
        # For now, return a placeholder - will implement when needed
        { success: false, error: 'get_pull_request not yet implemented with MCP' }
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Add a comment to a PR
    def add_comment(repo_full_name, pr_number, body)
      begin
        result = call_mcp_tool('create_issue', {
          owner: repo_full_name.split('/').first,
          repo: repo_full_name.split('/').last,
          title: "Comment on PR ##{pr_number}",
          body: body
        })

        if result[:success]
          { success: true, comment_id: 'mcp_comment' }
        else
          { success: false, error: result[:error] || 'Failed to add comment' }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Get file content from repository
    def get_file_content(repo_full_name, path, ref: nil)
      begin
        result = call_mcp_tool('get_file_contents', {
          owner: repo_full_name.split('/').first,
          repo: repo_full_name.split('/').last,
          path: path,
          ref: ref
        })

        if result[:success]
          {
            success: true,
            content: result[:content],
            sha: result[:sha] || 'unknown',
            encoding: 'utf-8'
          }
        else
          { success: false, error: "File not found: #{path}" }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Create or update a file
    def create_or_update_file(repo_full_name, path, content, message, branch, sha: nil)
      begin
        result = call_mcp_tool('create_or_update_file', {
          owner: repo_full_name.split('/').first,
          repo: repo_full_name.split('/').last,
          path: path,
          content: content,
          message: message,
          branch: branch,
          sha: sha
        })

        if result[:success]
          { success: true, commit_sha: result[:commit_sha] || 'unknown' }
        else
          { success: false, error: result[:error] || 'Failed to create/update file' }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Push multiple files at once
    def push_files(repo_full_name, branch, files, commit_message)
      begin
        # files format: [{ path: 'file1.rb', content: '...' }, { path: 'file2.rb', content: '...' }]
        result = call_mcp_tool('push_files', {
          owner: repo_full_name.split('/').first,
          repo: repo_full_name.split('/').last,
          branch: branch,
          files: files.map { |f| { path: f[:path], content: f[:content] } },
          message: commit_message
        })

        if result[:success]
          { success: true, commit_sha: result[:commit_sha] || 'unknown' }
        else
          { success: false, error: result[:error] || 'Failed to push files' }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Create a new branch
    def create_branch(repo_full_name, branch_name, from_branch: 'main')
      begin
        result = call_mcp_tool('create_branch', {
          owner: repo_full_name.split('/').first,
          repo: repo_full_name.split('/').last,
          branch: branch_name,
          from_branch: from_branch
        })

        if result[:success]
          { success: true, branch: branch_name, sha: result[:sha] || 'unknown' }
        else
          { success: false, error: result[:error] || "Branch already exists or invalid" }
        end
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Merge a pull request
    def merge_pull_request(repo_full_name, pr_number, commit_message: nil)
      begin
        # MCP GitHub server doesn't have merge_pull_request
        # This would need to be implemented or use direct API
        { success: false, error: 'merge_pull_request not yet implemented with MCP' }
      rescue => e
        { success: false, error: e.message }
      end
    end

    # Get repository file tree
    def get_repository_tree(repo_full_name, branch: 'main')
      begin
        # MCP GitHub server doesn't have a direct tree method
        # This would need to be implemented differently
        { success: false, error: 'get_repository_tree not yet implemented with MCP' }
      rescue => e
        { success: false, error: e.message }
      end
    end

    private

    # Call MCP tool with entity credentials
    def call_mcp_tool(tool_name, arguments)
      # Inject entity credentials into environment for MCP server
      original_env = ENV['GITHUB_PERSONAL_ACCESS_TOKEN']

      begin
        ENV['GITHUB_PERSONAL_ACCESS_TOKEN'] = @config[:token]

        # Call MCP tool through manager
        @mcp.call_tool('github', tool_name, arguments)
      ensure
        # Restore original environment
        ENV['GITHUB_PERSONAL_ACCESS_TOKEN'] = original_env
      end
    end

    # Parse repository list from MCP response
    def parse_repositories(content)
      return [] unless content.is_a?(Array)

      content.map do |repo|
        {
          name: repo['name'],
          full_name: repo['full_name'],
          default_branch: repo['default_branch'] || 'main'
        }
      end
    end

    # Parse PR response from MCP
    def parse_pr_response(content)
      if content.is_a?(Hash)
        {
          html_url: content['html_url'] || content['url'],
          number: content['number'] || content['id'],
          state: content['state'] || 'open'
        }
      else
        { html_url: '', number: 0, state: 'unknown' }
      end
    end

    def repo_full_name(repo_name = nil)
      repo_name || "#{@config[:organization]}/#{@config[:repository]}"
    end
  end
end
