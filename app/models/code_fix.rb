# frozen_string_literal: true

# CodeFix - A generated code change to fix an issue
#
# This model tracks:
# 1. The actual code changes (files modified)
# 2. Test results and validation
# 3. Git branch and commit info
# 4. Review and approval status
#
class CodeFix < ApplicationRecord
  belongs_to :debug_session
  belongs_to :support_ticket
  belongs_to :entity

  has_many :pull_request_submissions, dependent: :destroy

  STATUSES = %w[
    drafting
    testing
    test_failed
    validated
    rejected
    applied
    rolled_back
  ].freeze

  RISK_LEVELS = %w[low medium high critical].freeze
  FIX_TYPES = %w[hotfix refactor enhancement config_change].freeze

  validates :fix_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :risk_level, inclusion: { in: RISK_LEVELS }, allow_nil: true
  validates :fix_type, inclusion: { in: FIX_TYPES }, allow_nil: true

  before_validation :generate_fix_id, on: :create

  scope :pending, -> { where(status: %w[drafting testing]) }
  scope :validated, -> { where(status: 'validated') }
  scope :applied, -> { where(status: 'applied') }
  scope :recent, -> { order(created_at: :desc) }

  # ═══════════════════════════════════════════════════════════════════════════
  # FILE MANAGEMENT
  # ═══════════════════════════════════════════════════════════════════════════

  def add_file_change(path:, original_content:, modified_content:)
    require 'diffy'

    diff = Diffy::Diff.new(original_content, modified_content, context: 3).to_s(:text)

    files_modified << {
      path: path,
      original_content: original_content,
      modified_content: modified_content,
      diff: diff
    }

    self.files_changed_count = files_modified.length
    self.lines_added = (lines_added || 0) + modified_content.lines.count
    self.lines_removed = (lines_removed || 0) + original_content.lines.count
    save!
  end

  def file_paths
    files_modified.map { |f| f['path'] || f[:path] }
  end

  def diff_for_file(path)
    file = files_modified.find { |f| (f['path'] || f[:path]) == path }
    file&.dig('diff') || file&.dig(:diff)
  end

  def full_diff
    files_modified.map do |file|
      path = file['path'] || file[:path]
      diff = file['diff'] || file[:diff]
      "--- a/#{path}\n+++ b/#{path}\n#{diff}"
    end.join("\n\n")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # TESTING
  # ═══════════════════════════════════════════════════════════════════════════

  def start_testing!
    update!(status: 'testing')
    support_ticket.start_testing!
  end

  def record_test_results!(tests_run:, tests_passed:, tests_failed:, output:)
    update!(
      test_results: {
        tests_run: tests_run,
        tests_passed: tests_passed,
        tests_failed: tests_failed,
        test_output: output.truncate(10000),
        ran_at: Time.current.iso8601
      },
      tests_passed: tests_failed.zero?,
      status: tests_failed.zero? ? 'validated' : 'test_failed'
    )
  end

  def record_lint_results!(passed:, output:)
    update!(
      lint_passed: passed,
      validation_notes: output
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # GIT OPERATIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def create_branch!(branch_name: nil, base_commit: nil)
    branch_name ||= generate_branch_name
    update!(
      git_branch: branch_name,
      base_commit_sha: base_commit
    )
    git_branch
  end

  def record_commit!(commit_sha:)
    update!(git_commit_sha: commit_sha)
  end

  def generate_branch_name
    ticket_num = support_ticket.ticket_number.downcase.gsub('-', '_')
    "fix/#{ticket_num}_#{fix_id[0..7]}"
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # REVIEW
  # ═══════════════════════════════════════════════════════════════════════════

  def mark_validated!
    update!(status: 'validated')
  end

  def approve!(reviewer:, notes: nil)
    update!(
      review_decision: 'approved',
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      review_notes: notes
    )
  end

  def reject!(reviewer:, notes:)
    update!(
      status: 'rejected',
      review_decision: 'rejected',
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      review_notes: notes
    )
  end

  def request_changes!(reviewer:, notes:)
    update!(
      review_decision: 'needs_changes',
      reviewed_by: reviewer,
      reviewed_at: Time.current,
      review_notes: notes
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # APPLICATION
  # ═══════════════════════════════════════════════════════════════════════════

  def apply!(applied_by:)
    update!(
      status: 'applied',
      applied_at: Time.current,
      applied_by: applied_by
    )
    support_ticket.resolve!(resolved_by: applied_by, notes: "Fixed by #{fix_id}")
  end

  def rollback!(reason:, rolled_back_by:)
    update!(
      status: 'rolled_back',
      rolled_back_at: Time.current,
      rolled_back_by: rolled_back_by,
      rollback_reason: reason
    )
    support_ticket.update!(status: 'fixing', resolution_notes: nil, resolved_at: nil)
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # PR CREATION
  # ═══════════════════════════════════════════════════════════════════════════

  def create_pull_request!(pr_number:, pr_url:, pr_title:, pr_body:, source_branch: nil, target_branch: 'main')
    submission = pull_request_submissions.create!(
      support_ticket: support_ticket,
      entity: entity,
      pr_number: pr_number,
      pr_url: pr_url,
      pr_title: pr_title,
      pr_body: pr_body,
      source_branch: source_branch || git_branch,
      target_branch: target_branch,
      status: 'open'
    )

    support_ticket.pr_submitted!(pr_url)
    submission
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTEXT
  # ═══════════════════════════════════════════════════════════════════════════

  def to_context
    {
      fix_id: fix_id,
      status: status,
      description: fix_description,
      risk_level: risk_level,
      files: file_paths,
      diff: full_diff,
      tests_passed: tests_passed,
      git_branch: git_branch,
      review_decision: review_decision
    }
  end

  private

  def generate_fix_id
    return if fix_id.present?

    self.fix_id = "fix_#{SecureRandom.uuid[0..11]}"
  end
end


