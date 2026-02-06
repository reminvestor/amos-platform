# frozen_string_literal: true

# GitHubWebhookService - Processes inbound GitHub webhook events
#
# Connects GitHub activity to the AMOS bounty and pipeline systems:
#
# 1. AUTO-LINK: Parses PR titles/bodies for bounty references
#    - "Fixes bounty #123" or "Bounty #123"
#    - "AMOS-00042" (ticket number)
#    - "bounty:123" in branch name
#
# 2. STATUS SYNC: Updates PullRequestSubmission and Bounty status
#    - PR opened → bounty marked 'in_progress'
#    - PR approved → bounty ready for merge
#    - PR merged → bounty auto-submitted for review → AI review → tokens
#
# 3. PIPELINE EVENTS: Creates PipelineEvent records for the AI pipeline
#    - pr.opened, pr.approved, pr.merged, tests.passed/failed
#
# 4. EAP WEBHOOKS: Fires webhooks for external agent bounties
#
class GithubWebhookService
  # Patterns to match bounty references in PR titles/bodies/branches
  BOUNTY_PATTERNS = [
    /\b(?:bounty|fixes bounty|closes bounty|resolves bounty)\s*#?(\d+)/i,
    /\bAMOS-(\d{4,5})\b/,                        # Ticket number → find linked bounty
    /\bbounty[:\-_](\d+)/i,                       # bounty:123 or bounty-123
  ].freeze

  TICKET_PATTERNS = [
    /\bAMOS-(\d{4,5})\b/,                        # Ticket number
    /\b(?:ticket|issue|fixes|closes)\s*#?AMOS-(\d{4,5})/i,
  ].freeze

  class << self
    # Main entry point — dispatches to the correct handler
    def process(event_type:, payload:, delivery_id: nil)
      Rails.logger.info "[GitHub] Processing #{event_type} event (delivery: #{delivery_id})"

      case event_type
      when 'pull_request'
        handle_pull_request(payload)
      when 'pull_request_review'
        handle_pull_request_review(payload)
      when 'check_run'
        handle_check_run(payload)
      when 'check_suite'
        handle_check_suite(payload)
      when 'issues'
        handle_issue(payload)
      when 'ping'
        Rails.logger.info "[GitHub] Ping received — webhook is connected"
      else
        Rails.logger.debug "[GitHub] Ignoring event type: #{event_type}"
      end
    rescue => e
      Rails.logger.error "[GitHub] Error processing #{event_type}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
      raise # Let the job retry
    end

    private

    # ═══════════════════════════════════════════════════════════════════════════
    # PULL REQUEST EVENTS
    # ═══════════════════════════════════════════════════════════════════════════

    def handle_pull_request(payload)
      action = payload['action']
      pr = payload['pull_request']
      repo = payload['repository']

      pr_number = pr['number']
      pr_url = pr['html_url']
      pr_title = pr['title']
      pr_body = pr['body'] || ''
      pr_branch = pr['head']['ref']
      pr_author = pr.dig('user', 'login')
      merged = pr['merged'] || false

      Rails.logger.info "[GitHub] PR ##{pr_number} #{action}: #{pr_title}"

      case action
      when 'opened', 'reopened'
        handle_pr_opened(pr_number, pr_url, pr_title, pr_body, pr_branch, pr_author, repo)
      when 'closed'
        if merged
          handle_pr_merged(pr_number, pr_url, pr_title, pr_body, pr_branch, pr_author, pr, repo)
        else
          handle_pr_closed(pr_number, repo)
        end
      when 'synchronize'
        # New commits pushed — could re-trigger CI
        Rails.logger.info "[GitHub] PR ##{pr_number} updated with new commits"
      end
    end

    def handle_pr_opened(pr_number, pr_url, pr_title, pr_body, pr_branch, author, repo)
      # 1. Find linked bounties
      bounty = find_linked_bounty(pr_title, pr_body, pr_branch)
      ticket = find_linked_ticket(pr_title, pr_body)

      # 2. Link PR to bounty
      if bounty
        Rails.logger.info "[GitHub] Linking PR ##{pr_number} to Bounty ##{bounty.id}: #{bounty.title}"

        bounty.update!(
          pr_url: pr_url,
          pr_number: pr_number,
          branch_name: pr_branch,
          status: bounty.status == 'open' ? 'claimed' : bounty.status
        )

        # If bounty is open, mark as in_progress
        bounty.start_work! if bounty.claimed?
      end

      # 3. Update existing PullRequestSubmission if it exists
      pr_submission = find_pr_submission(pr_number, repo)
      if pr_submission
        pr_submission.mark_open!
        Rails.logger.info "[GitHub] Updated existing PR submission for ##{pr_number}"
      end

      # 4. Create pipeline event
      create_pipeline_event('pr.opened', {
        pr_number: pr_number,
        pr_url: pr_url,
        title: pr_title,
        author: author,
        branch: pr_branch,
        bounty_id: bounty&.id,
        ticket_number: ticket&.ticket_number
      })
    end

    def handle_pr_merged(pr_number, pr_url, pr_title, pr_body, pr_branch, author, pr_data, repo)
      merge_sha = pr_data['merge_commit_sha']

      Rails.logger.info "[GitHub] PR ##{pr_number} merged (sha: #{merge_sha})"

      # 1. Find linked bounty
      bounty = find_linked_bounty(pr_title, pr_body, pr_branch)
      # Also check by pr_number on the bounty record
      bounty ||= Bounty.find_by(pr_number: pr_number)

      # 2. Update PR submission
      pr_submission = find_pr_submission(pr_number, repo)
      if pr_submission
        pr_submission.merge!(merged_by: author, merge_commit_sha: merge_sha)
      end

      # 3. Auto-advance bounty on merge
      if bounty
        Rails.logger.info "[GitHub] Auto-advancing Bounty ##{bounty.id} after PR merge"
        auto_advance_bounty_on_merge!(bounty, pr_number, pr_url, merge_sha, author)
      end

      # 4. Update ticket if linked
      ticket = find_linked_ticket(pr_title, pr_body)
      ticket ||= bounty&.support_ticket
      if ticket && ticket.is_open?
        ticket.resolve!(notes: "Resolved via PR ##{pr_number} merge", resolved_by: author)
      end

      # 5. Create pipeline event
      create_pipeline_event('pr.merged', {
        pr_number: pr_number,
        pr_url: pr_url,
        merge_sha: merge_sha,
        author: author,
        bounty_id: bounty&.id,
        ticket_number: ticket&.ticket_number
      })
    end

    def handle_pr_closed(pr_number, repo)
      Rails.logger.info "[GitHub] PR ##{pr_number} closed without merge"

      pr_submission = find_pr_submission(pr_number, repo)
      pr_submission&.close!(closed_by: 'github', reason: 'PR closed without merge')

      # Release bounty claim if linked
      bounty = Bounty.find_by(pr_number: pr_number)
      if bounty && bounty.status.in?(%w[claimed in_progress])
        bounty.release_claim! if bounty.respond_to?(:release_claim!)
        Rails.logger.info "[GitHub] Released bounty ##{bounty.id} claim (PR closed)"
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PULL REQUEST REVIEW EVENTS
    # ═══════════════════════════════════════════════════════════════════════════

    def handle_pull_request_review(payload)
      action = payload['action']
      return unless action == 'submitted'

      review = payload['review']
      pr = payload['pull_request']
      pr_number = pr['number']
      reviewer = review.dig('user', 'login')
      state = review['state'] # approved, changes_requested, commented

      Rails.logger.info "[GitHub] PR ##{pr_number} review: #{state} by #{reviewer}"

      case state
      when 'approved'
        # Update PR submission
        pr_submission = find_pr_submission(pr_number, payload['repository'])
        pr_submission&.add_review_comment!(reviewer: reviewer, comment: review['body'] || 'Approved', approved: true)

        create_pipeline_event('pr.approved', {
          pr_number: pr_number,
          reviewer: reviewer
        })

      when 'changes_requested'
        pr_submission = find_pr_submission(pr_number, payload['repository'])
        pr_submission&.request_changes!(reviewer: reviewer, comments: review['body'] || 'Changes requested')

        create_pipeline_event('pr.needs_changes', {
          pr_number: pr_number,
          reviewer: reviewer,
          comments: review['body']
        })
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CI/CD EVENTS
    # ═══════════════════════════════════════════════════════════════════════════

    def handle_check_run(payload)
      check_run = payload['check_run']
      status = check_run['status']       # queued, in_progress, completed
      conclusion = check_run['conclusion'] # success, failure, neutral, etc.
      name = check_run['name']

      return unless status == 'completed'

      # Find associated PR(s)
      prs = check_run['pull_requests'] || []
      prs.each do |pr|
        pr_number = pr['number']
        pr_submission = find_pr_submission(pr_number, payload['repository'])
        next unless pr_submission

        ci_status = conclusion == 'success' ? 'passed' : 'failed'
        pr_submission.update_ci_status!(
          status: ci_status,
          results: { check_name: name, conclusion: conclusion, completed_at: check_run['completed_at'] }
        )

        event_type = ci_status == 'passed' ? 'tests.passed' : 'tests.failed'
        create_pipeline_event(event_type, {
          pr_number: pr_number,
          check_name: name,
          conclusion: conclusion
        })

        Rails.logger.info "[GitHub] CI #{ci_status} for PR ##{pr_number} (#{name})"
      end
    end

    def handle_check_suite(payload)
      # Similar to check_run but for the entire suite
      suite = payload['check_suite']
      return unless suite['status'] == 'completed'

      conclusion = suite['conclusion']
      prs = suite['pull_requests'] || []

      prs.each do |pr|
        pr_number = pr['number']
        pr_submission = find_pr_submission(pr_number, payload['repository'])
        next unless pr_submission

        ci_status = conclusion == 'success' ? 'passed' : 'failed'
        pr_submission.update_ci_status!(status: ci_status, results: { suite_conclusion: conclusion })
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # ISSUE EVENTS
    # ═══════════════════════════════════════════════════════════════════════════

    def handle_issue(payload)
      # Could be used for community bounty creation from GitHub issues
      Rails.logger.debug "[GitHub] Issue event: #{payload['action']} ##{payload.dig('issue', 'number')}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # BOUNTY AUTO-ADVANCEMENT
    # ═══════════════════════════════════════════════════════════════════════════

    def auto_advance_bounty_on_merge!(bounty, pr_number, pr_url, merge_sha, author)
      # Update bounty with PR merge data
      bounty.update!(
        pr_url: pr_url,
        pr_number: pr_number,
        commit_sha: merge_sha
      )

      # Submit the bounty for review (transition: in_progress → submitted)
      unless bounty.status.in?(%w[submitted reviewing approved])
        bounty.submit!(
          notes: "Auto-submitted: PR ##{pr_number} merged by #{author}",
          pr_url: pr_url,
          commit_sha: merge_sha
        )
        Rails.logger.info "[GitHub] Bounty ##{bounty.id} auto-submitted for review"
      end

      # Trigger AI review
      if bounty.status == 'submitted'
        BountyAiReviewJob.perform_later(bounty.id) if defined?(BountyAiReviewJob)
        Rails.logger.info "[GitHub] Triggered AI review for Bounty ##{bounty.id}"
      end

      # If bounty is linked to an external agent execution, advance that too
      if bounty.respond_to?(:external_agent_executions)
        bounty.external_agent_executions.where(status: 'in_progress').each do |execution|
          execution.submit!(
            work_summary: "PR ##{pr_number} merged (#{merge_sha[0..7]})",
            deliverables: { pr_url: pr_url, merge_sha: merge_sha }
          )
          Rails.logger.info "[GitHub] External agent execution #{execution.id} auto-submitted"
        end
      end
    rescue => e
      Rails.logger.error "[GitHub] Failed to auto-advance bounty ##{bounty.id}: #{e.message}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # LINKING HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def find_linked_bounty(title, body, branch)
      text = "#{title}\n#{body}\n#{branch}"

      # Try bounty ID patterns
      BOUNTY_PATTERNS.each do |pattern|
        match = text.match(pattern)
        if match
          bounty_id = match[1].to_i
          # Check if it's a ticket number (AMOS-XXXXX) or bounty ID
          if match[0].include?('AMOS-')
            ticket = SupportTicket.find_by(ticket_number: "AMOS-#{match[1].rjust(5, '0')}")
            return ticket.bounty if ticket&.bounty
          else
            bounty = Bounty.find_by(id: bounty_id)
            return bounty if bounty
          end
        end
      end

      nil
    end

    def find_linked_ticket(title, body)
      text = "#{title}\n#{body}"

      TICKET_PATTERNS.each do |pattern|
        match = text.match(pattern)
        if match
          ticket_number = "AMOS-#{match[1].rjust(5, '0')}"
          ticket = SupportTicket.find_by(ticket_number: ticket_number)
          return ticket if ticket
        end
      end

      nil
    end

    def find_pr_submission(pr_number, repo_payload)
      # Try to find by PR number
      PullRequestSubmission.find_by(pr_number: pr_number)
    rescue
      nil
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # PIPELINE INTEGRATION
    # ═══════════════════════════════════════════════════════════════════════════

    def create_pipeline_event(event_type, metadata)
      # Find active pipeline execution for this PR
      pr_number = metadata[:pr_number]
      return unless pr_number

      # Look for pipeline execution linked to this PR
      execution = PipelineExecution.where(
        "metadata->>'pr_number' = ? OR metadata->>'pr_id' = ?",
        pr_number.to_s, pr_number.to_s
      ).where.not(status: %w[done failed rolled_back]).first

      if execution
        execution.create_event!(
          event_type: event_type,
          source: 'github',
          metadata: metadata
        )
        Rails.logger.info "[GitHub] Created pipeline event #{event_type} for execution #{execution.id}"

        # Trigger state transitions based on event
        handle_pipeline_transition(execution, event_type)
      end
    rescue => e
      Rails.logger.warn "[GitHub] Failed to create pipeline event: #{e.message}"
    end

    def handle_pipeline_transition(execution, event_type)
      case event_type
      when 'pr.opened'
        # PR opened → move to review state
        if AiAgents::Pipeline::StateMachine.can_transition?(execution.status, 'review')
          execution.transition_to!('review')
        end
      when 'pr.approved'
        # PR approved → move to testing
        if AiAgents::Pipeline::StateMachine.can_transition?(execution.status, 'testing')
          execution.transition_to!('testing')
        end
      when 'tests.passed'
        # Tests passed → move to dev
        if AiAgents::Pipeline::StateMachine.can_transition?(execution.status, 'dev')
          execution.transition_to!('dev')
        end
      when 'pr.merged'
        # PR merged to main/dev → move toward staging/prod
        if AiAgents::Pipeline::StateMachine.can_transition?(execution.status, 'staging')
          execution.transition_to!('staging')
        end
      when 'tests.failed'
        # Tests failed → back to implementing
        if AiAgents::Pipeline::StateMachine.can_transition?(execution.status, 'implementing')
          execution.transition_to!('implementing')
        end
      end
    rescue => e
      Rails.logger.warn "[GitHub] Pipeline transition failed: #{e.message}"
    end
  end
end
