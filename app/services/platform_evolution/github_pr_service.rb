# frozen_string_literal: true

module PlatformEvolution
  # GitHubPRService - Creates and manages Pull Requests on GitHub
  #
  # This service:
  # 1. Creates PRs from validated code fixes
  # 2. Tracks PR status and reviews
  # 3. Handles merge operations
  # 4. Syncs PR state with our records
  #
  class GitHubPRService
    attr_reader :code_fix, :access_token, :repo_owner, :repo_name

    def initialize(code_fix, options = {})
      @code_fix = code_fix
      @access_token = options[:access_token] || ENV['GITHUB_ACCESS_TOKEN']
      @repo_owner = options[:repo_owner] || ENV['GITHUB_REPO_OWNER']
      @repo_name = options[:repo_name] || ENV['GITHUB_REPO_NAME']
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PR CREATION
    # ═══════════════════════════════════════════════════════════════════════════

    def create_pull_request!(target_branch: 'main', reviewers: [])
      raise "Code fix not validated" unless code_fix.tests_passed

      # First, push the branch
      push_branch!

      # Create the PR
      pr_data = create_pr(
        title: generate_pr_title,
        body: generate_pr_body,
        head: code_fix.git_branch,
        base: target_branch
      )

      return nil unless pr_data

      # Record the PR
      submission = code_fix.create_pull_request!(
        pr_number: pr_data['number'],
        pr_url: pr_data['html_url'],
        pr_title: pr_data['title'],
        pr_body: pr_data['body'],
        source_branch: code_fix.git_branch,
        target_branch: target_branch
      )

      # Request reviews if specified
      if reviewers.any?
        request_reviews(pr_data['number'], reviewers)
        submission.request_review!(reviewers: reviewers)
      end

      Rails.logger.info "[GitHubPR] Created PR ##{pr_data['number']}: #{pr_data['html_url']}"

      submission
    end

    def push_branch!
      git = PlatformEvolution::GitService.new
      git.push(code_fix.git_branch)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PR CONTENT GENERATION
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_pr_title
      ticket = code_fix.support_ticket
      "Fix: [#{ticket.ticket_number}] #{ticket.title.truncate(60)}"
    end

    def generate_pr_body
      ticket = code_fix.support_ticket
      session = code_fix.debug_session

      <<~BODY
        ## 🤖 Automated Fix by Platform Evolution Engine

        **Ticket:** #{ticket.ticket_number}
        **Priority:** #{ticket.priority}
        **Category:** #{ticket.category}

        ### Issue
        #{ticket.description}

        ### Root Cause
        #{session.root_cause_analysis}

        ### Changes Made
        #{format_changes}

        ### Testing
        - Tests Run: #{code_fix.test_results['tests_run'] || 0}
        - Tests Passed: #{code_fix.test_results['tests_passed'] || 0}
        - Lint Check: #{code_fix.lint_passed ? '✅ Passed' : '❌ Failed'}

        ### Files Changed
        #{code_fix.file_paths.map { |f| "- `#{f}`" }.join("\n")}

        ---

        > ⚠️ **This PR was automatically generated.** Please review carefully before merging.
        >
        > Debug Session: `#{session.session_id}`
        > Fix ID: `#{code_fix.fix_id}`
        > Risk Level: **#{code_fix.risk_level&.upcase}**
      BODY
    end

    def format_changes
      code_fix.files_modified.map do |file|
        path = file['path'] || file[:path]
        diff = file['diff'] || file[:diff]
        <<~CHANGE
          <details>
          <summary><code>#{path}</code></summary>

          ```diff
          #{diff}
          ```

          </details>
        CHANGE
      end.join("\n")
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # GITHUB API CALLS
    # ═══════════════════════════════════════════════════════════════════════════

    def create_pr(title:, body:, head:, base:)
      make_request(
        method: :post,
        path: "/repos/#{repo_owner}/#{repo_name}/pulls",
        body: {
          title: title,
          body: body,
          head: head,
          base: base
        }
      )
    end

    def request_reviews(pr_number, reviewers)
      make_request(
        method: :post,
        path: "/repos/#{repo_owner}/#{repo_name}/pulls/#{pr_number}/requested_reviewers",
        body: { reviewers: reviewers }
      )
    end

    def get_pr_status(pr_number)
      make_request(
        method: :get,
        path: "/repos/#{repo_owner}/#{repo_name}/pulls/#{pr_number}"
      )
    end

    def merge_pr(pr_number, commit_message: nil)
      make_request(
        method: :put,
        path: "/repos/#{repo_owner}/#{repo_name}/pulls/#{pr_number}/merge",
        body: {
          commit_message: commit_message || "Merge: Automated fix",
          merge_method: 'squash'
        }
      )
    end

    def close_pr(pr_number)
      make_request(
        method: :patch,
        path: "/repos/#{repo_owner}/#{repo_name}/pulls/#{pr_number}",
        body: { state: 'closed' }
      )
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # STATUS SYNC
    # ═══════════════════════════════════════════════════════════════════════════

    def sync_pr_status!(submission)
      pr_data = get_pr_status(submission.pr_number)
      return unless pr_data

      # Update status based on GitHub state
      new_status = case pr_data['state']
                   when 'open'
                     if pr_data['merged']
                       'merged'
                     elsif pr_data.dig('requested_reviewers')&.any?
                       'review_requested'
                     else
                       'open'
                     end
                   when 'closed'
                     pr_data['merged'] ? 'merged' : 'closed'
                   else
                     submission.status
                   end

      submission.update!(status: new_status)

      # If merged, apply the fix
      if new_status == 'merged' && !code_fix.applied_at
        submission.merge!(
          merged_by: pr_data.dig('merged_by', 'login') || 'github',
          merge_commit_sha: pr_data['merge_commit_sha']
        )
      end
    end

    private

    def make_request(method:, path:, body: nil)
      return mock_response(method, path, body) unless access_token.present?

      uri = URI("https://api.github.com#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = case method
                when :get
                  Net::HTTP::Get.new(uri)
                when :post
                  req = Net::HTTP::Post.new(uri)
                  req.body = body.to_json if body
                  req
                when :put
                  req = Net::HTTP::Put.new(uri)
                  req.body = body.to_json if body
                  req
                when :patch
                  req = Net::HTTP::Patch.new(uri)
                  req.body = body.to_json if body
                  req
                end

      request['Authorization'] = "Bearer #{access_token}"
      request['Accept'] = 'application/vnd.github.v3+json'
      request['Content-Type'] = 'application/json'

      response = http.request(request)

      if response.code.to_i >= 200 && response.code.to_i < 300
        JSON.parse(response.body)
      else
        Rails.logger.error "[GitHubPR] API error: #{response.code} - #{response.body}"
        nil
      end
    rescue => e
      Rails.logger.error "[GitHubPR] Request failed: #{e.message}"
      nil
    end

    def mock_response(method, path, body)
      # Return mock data when no GitHub token is configured
      Rails.logger.info "[GitHubPR] MOCK: #{method} #{path}"

      case method
      when :post
        if path.include?('/pulls')
          {
            'number' => rand(1000..9999),
            'html_url' => "https://github.com/#{repo_owner}/#{repo_name}/pull/#{rand(1000..9999)}",
            'title' => body[:title],
            'body' => body[:body],
            'state' => 'open'
          }
        end
      when :get
        {
          'state' => 'open',
          'merged' => false,
          'requested_reviewers' => []
        }
      else
        {}
      end
    end
  end
end


