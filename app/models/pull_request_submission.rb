# frozen_string_literal: true

# PullRequestSubmission - Tracks PRs submitted to GitHub/GitLab
#
class PullRequestSubmission < ApplicationRecord
  belongs_to :code_fix
  belongs_to :support_ticket
  belongs_to :entity

  STATUSES = %w[
    pending
    open
    review_requested
    approved
    changes_requested
    merged
    closed
  ].freeze

  CI_STATUSES = %w[pending running passed failed].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :open_prs, -> { where(status: %w[open review_requested approved changes_requested]) }
  scope :merged, -> { where(status: 'merged') }
  scope :pending_review, -> { where(status: %w[open review_requested]) }
  scope :recent, -> { order(created_at: :desc) }

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS UPDATES
  # ═══════════════════════════════════════════════════════════════════════════

  def mark_open!
    update!(status: 'open')
  end

  def request_review!(reviewers: [])
    update!(
      status: 'review_requested',
      reviewers: reviewers
    )
  end

  def add_review_comment!(reviewer:, comment:, approved: false)
    review_comments << {
      reviewer: reviewer,
      comment: comment,
      approved: approved,
      commented_at: Time.current.iso8601
    }
    increment!(:review_count)
    increment!(:approval_count) if approved
    save!

    if approved
      update!(status: 'approved')
      code_fix.approve!(reviewer: reviewer, notes: comment)
      support_ticket.pr_approved!
    end
  end

  def request_changes!(reviewer:, comments:)
    update!(status: 'changes_requested')
    add_review_comment!(reviewer: reviewer, comment: comments, approved: false)
    code_fix.request_changes!(reviewer: reviewer, notes: comments)
  end

  def merge!(merged_by:, merge_commit_sha:)
    update!(
      status: 'merged',
      merged_at: Time.current,
      merged_by: merged_by,
      merge_commit_sha: merge_commit_sha
    )
    code_fix.apply!(applied_by: merged_by)
  end

  def close!(closed_by:, reason:)
    update!(
      status: 'closed',
      closed_at: Time.current,
      closed_by: closed_by,
      close_reason: reason
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CI/CD
  # ═══════════════════════════════════════════════════════════════════════════

  def update_ci_status!(status:, results: {})
    update!(
      ci_status: status,
      ci_results: ci_results.merge(results).merge(updated_at: Time.current.iso8601)
    )
  end

  def ci_passed?
    ci_status == 'passed'
  end

  def ci_failed?
    ci_status == 'failed'
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # QUERIES
  # ═══════════════════════════════════════════════════════════════════════════

  def is_open?
    %w[open review_requested approved changes_requested].include?(status)
  end

  def is_approved?
    status == 'approved' || approval_count.positive?
  end

  def is_merged?
    status == 'merged'
  end

  def ready_to_merge?
    is_approved? && ci_passed?
  end

  def to_context
    {
      pr_number: pr_number,
      pr_url: pr_url,
      status: status,
      reviewers: reviewers,
      approval_count: approval_count,
      ci_status: ci_status,
      merged: is_merged?
    }
  end
end


