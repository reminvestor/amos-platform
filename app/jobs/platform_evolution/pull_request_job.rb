# frozen_string_literal: true

module PlatformEvolution
  # PullRequestJob - Creates PR on GitHub for validated fix
  #
  class PullRequestJob < ApplicationJob
    queue_as :default

    def perform(code_fix_id, options = {})
      code_fix = CodeFix.find(code_fix_id)
      ticket = code_fix.support_ticket

      Rails.logger.info "[PullRequestJob] Creating PR for #{ticket.ticket_number}"

      service = GithubPrService.new(code_fix)
      submission = service.create_pull_request!(
        target_branch: options[:target_branch] || 'main',
        reviewers: options[:reviewers] || []
      )

      if submission
        Rails.logger.info "[PullRequestJob] Created PR ##{submission.pr_number} for #{ticket.ticket_number}"

        # Notify if configured
        if options[:notify_slack]
          notify_pr_created(submission)
        end
      end
    rescue => e
      Rails.logger.error "[PullRequestJob] Error creating PR for fix #{code_fix_id}: #{e.message}"
      raise if options[:raise_on_error]
    end

    private

    def notify_pr_created(submission)
      # Slack notification would go here
      Rails.logger.info "[PullRequestJob] Would notify about PR: #{submission.pr_url}"
    end
  end
end


