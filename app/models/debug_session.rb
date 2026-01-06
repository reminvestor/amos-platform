# frozen_string_literal: true

# DebugSession - Interactive debugging conversation for a support ticket
#
# This model tracks the debugging process including:
# 1. Conversation with user/agent gathering information
# 2. Analysis findings (logs, code review, patterns)
# 3. Root cause determination
# 4. Proposed fixes with confidence scores
#
class DebugSession < ApplicationRecord
  belongs_to :support_ticket
  belongs_to :entity
  belongs_to :user, optional: true

  has_many :code_fixes, dependent: :destroy

  STATUSES = %w[
    gathering_info
    analyzing
    reproducing
    proposing_fix
    awaiting_approval
    completed
    abandoned
  ].freeze

  validates :session_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :generate_session_id, on: :create

  scope :active, -> { where(status: %w[gathering_info analyzing reproducing proposing_fix]) }
  scope :completed, -> { where(status: 'completed') }
  scope :recent, -> { order(created_at: :desc) }

  # ═══════════════════════════════════════════════════════════════════════════
  # CONVERSATION MANAGEMENT
  # ═══════════════════════════════════════════════════════════════════════════

  def add_message(role:, content:, metadata: {})
    conversation_history << {
      role: role,  # 'user', 'agent', 'system'
      content: content,
      timestamp: Time.current.iso8601,
      metadata: metadata
    }
    save!
  end

  def add_user_message(content)
    add_message(role: 'user', content: content)
  end

  def add_agent_message(content, metadata: {})
    add_message(role: 'agent', content: content, metadata: metadata)
  end

  def add_system_message(content)
    add_message(role: 'system', content: content)
  end

  def last_message
    conversation_history.last
  end

  def messages_for_context
    conversation_history.map do |msg|
      { role: msg['role'], content: msg['content'] }
    end
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # ANALYSIS & FINDINGS
  # ═══════════════════════════════════════════════════════════════════════════

  def add_finding(type:, content:, source:)
    findings[type] ||= []
    findings[type] << {
      content: content,
      source: source,
      found_at: Time.current.iso8601
    }
    save!
  end

  def add_log_finding(log_content, source: 'log_file')
    add_finding(type: 'logs', content: log_content, source: source)
  end

  def add_code_finding(file_path:, content:, issue:)
    add_finding(
      type: 'code',
      content: { file: file_path, code: content, issue: issue },
      source: 'code_review'
    )
  end

  def add_pattern_finding(pattern:, occurrences:)
    add_finding(
      type: 'patterns',
      content: { pattern: pattern, occurrences: occurrences },
      source: 'pattern_analysis'
    )
  end

  def set_root_cause!(analysis:, confidence:)
    update!(
      root_cause_analysis: analysis,
      confidence_score: confidence
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # FIX PROPOSALS
  # ═══════════════════════════════════════════════════════════════════════════

  def add_proposed_fix(description:, files:, risk_level:, estimated_impact:)
    proposed_fixes << {
      index: proposed_fixes.length,
      description: description,
      files: files,
      risk_level: risk_level,
      estimated_impact: estimated_impact,
      proposed_at: Time.current.iso8601
    }
    save!
    proposed_fixes.last
  end

  def select_fix!(index:, rationale:)
    raise "Invalid fix index" unless proposed_fixes[index]

    update!(
      selected_fix_index: index,
      fix_rationale: rationale,
      status: 'awaiting_approval'
    )
  end

  def selected_fix
    return nil unless selected_fix_index

    proposed_fixes[selected_fix_index]
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # STATUS TRANSITIONS
  # ═══════════════════════════════════════════════════════════════════════════

  def start_analysis!
    update!(status: 'analyzing')
    support_ticket.start_investigation! if support_ticket.status == 'open'
  end

  def start_reproduction!
    update!(status: 'reproducing')
  end

  def mark_reproduced!(steps:, results:)
    update!(
      reproduced: true,
      reproduction_steps: steps,
      reproduction_results: results
    )
  end

  def start_proposing_fix!
    update!(status: 'proposing_fix')
    support_ticket.start_fixing!
  end

  def complete!(notes: nil)
    update!(
      status: 'completed',
      completed_at: Time.current
    )
    add_system_message("Debug session completed. #{notes}")
  end

  def abandon!(reason:)
    update!(status: 'abandoned', completed_at: Time.current)
    add_system_message("Debug session abandoned: #{reason}")
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CODE FIX CREATION
  # ═══════════════════════════════════════════════════════════════════════════

  def create_code_fix!(files_modified:, fix_description: nil, risk_level: 'medium')
    support_ticket.increment!(:code_fix_attempts)

    code_fixes.create!(
      support_ticket: support_ticket,
      entity: entity,
      fix_description: fix_description || selected_fix&.dig(:description) || 'Automated fix',
      risk_level: risk_level,
      files_modified: files_modified,
      files_changed_count: files_modified.length,
      lines_added: files_modified.sum { |f| f[:modified_content]&.lines&.count || 0 },
      lines_removed: files_modified.sum { |f| f[:original_content]&.lines&.count || 0 }
    )
  end

  # ═══════════════════════════════════════════════════════════════════════════
  # CONTEXT FOR AI
  # ═══════════════════════════════════════════════════════════════════════════

  def to_context
    {
      session_id: session_id,
      status: status,
      ticket: support_ticket.to_context,
      conversation: messages_for_context,
      findings: findings,
      root_cause: root_cause_analysis,
      confidence: confidence_score,
      proposed_fixes: proposed_fixes,
      selected_fix: selected_fix
    }
  end

  private

  def generate_session_id
    return if session_id.present?

    self.session_id = "dbg_#{SecureRandom.uuid}"
  end
end


