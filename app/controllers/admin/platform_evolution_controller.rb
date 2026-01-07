# frozen_string_literal: true

module Admin
  class PlatformEvolutionController < Admin::BaseController
    before_action :set_ticket, only: [:show_ticket, :debug_ticket, :approve_fix, :reject_fix, :merge_pr]
    helper_method :status_badge_class, :session_status_class, :confidence_class, :risk_badge_class, :conversation_bg_class, :pr_status_class

    def status_badge_class(status)
      case status.to_s
      when 'open' then 'info'
      when 'investigating', 'debugging' then 'warning'
      when 'fixing', 'testing' then 'primary'
      when 'pr_submitted', 'pr_approved' then 'info'
      when 'resolved', 'closed' then 'success'
      when 'wont_fix' then 'secondary'
      when 'validated', 'pending' then 'info'
      when 'approved' then 'success'
      when 'rejected' then 'danger'
      else 'secondary'
      end
    end

    def session_status_class(status)
      case status.to_s
      when 'gathering_info' then 'info'
      when 'analyzing' then 'warning'
      when 'reproducing' then 'warning'
      when 'proposing_fix' then 'primary'
      when 'awaiting_approval' then 'info'
      when 'completed' then 'success'
      when 'abandoned' then 'secondary'
      else 'secondary'
      end
    end

    def confidence_class(score)
      return 'secondary' unless score
      case score
      when 0.8..1.0 then 'success'
      when 0.5..0.8 then 'warning'
      else 'danger'
      end
    end

    def risk_badge_class(level)
      case level.to_s.downcase
      when 'low' then 'success'
      when 'medium' then 'warning'
      when 'high' then 'danger'
      when 'critical' then 'danger'
      else 'secondary'
      end
    end

    def conversation_bg_class(role)
      case role.to_s
      when 'user' then 'bg-primary bg-opacity-10'
      when 'agent' then 'bg-success bg-opacity-10'
      when 'system' then 'bg-light'
      else 'bg-light'
      end
    end

    def pr_status_class(status)
      case status.to_s
      when 'pending_review' then 'warning'
      when 'approved' then 'info'
      when 'merged' then 'success'
      when 'closed' then 'secondary'
      else 'secondary'
      end
    end

    # GET /admin/platform_evolution
    def index
      @stats = calculate_stats

      @open_tickets = SupportTicket.open_tickets.order(priority: :desc, created_at: :desc).limit(20)
      @pending_prs = PullRequestSubmission.pending_review.includes(:code_fix, :support_ticket).limit(10)
      @recent_fixes = CodeFix.validated.order(created_at: :desc).limit(10)
      @recent_merges = PullRequestSubmission.merged.order(merged_at: :desc).limit(10)
    end

    # GET /admin/platform_evolution/tickets
    def tickets
      @tickets = SupportTicket.includes(:user, :debug_sessions).order(created_at: :desc)

      # Filters
      @tickets = @tickets.where(status: params[:status]) if params[:status].present?
      @tickets = @tickets.where(priority: params[:priority]) if params[:priority].present?
      @tickets = @tickets.where(source: params[:source]) if params[:source].present?
      @tickets = @tickets.where(category: params[:category]) if params[:category].present?

      @tickets = @tickets.page(params[:page]).per(30)
    end

    # GET /admin/platform_evolution/ticket/:id
    def show_ticket
      @debug_sessions = @ticket.debug_sessions.order(created_at: :desc)
      @code_fixes = @ticket.code_fixes.order(created_at: :desc)
      @prs = @ticket.pull_request_submissions.order(created_at: :desc)
    end

    # POST /admin/platform_evolution/ticket/:id/debug
    def debug_ticket
      PlatformEvolution::DebugAgentJob.perform_later(@ticket.id)
      redirect_to ticket_admin_platform_evolution_path(@ticket), notice: "Debug session started"
    end

    # GET /admin/platform_evolution/debug_sessions
    def debug_sessions
      @sessions = DebugSession.includes(:support_ticket, :user).order(created_at: :desc)
      @sessions = @sessions.where(status: params[:status]) if params[:status].present?
      @sessions = @sessions.page(params[:page]).per(30)
    end

    # GET /admin/platform_evolution/debug_session/:id
    def show_debug_session
      @session = DebugSession.find(params[:id])
      @ticket = @session.support_ticket
      @code_fixes = @session.code_fixes.order(created_at: :desc)
    end

    # POST /admin/platform_evolution/debug_session/:id/retry
    def retry_debug_session
      session = DebugSession.find(params[:id])
      ticket = session.support_ticket

      # Mark old session as abandoned
      session.abandon!(reason: "Retrying with new session")

      # Start a new debug session
      PlatformEvolution::DebugAgentJob.perform_later(ticket.id)

      redirect_to ticket_admin_platform_evolution_path(ticket), notice: "New debug session started"
    end

    # POST /admin/platform_evolution/debug_session/:id/mark_failed
    def mark_session_failed
      session = DebugSession.find(params[:id])
      session.abandon!(reason: params[:reason] || "Marked as failed by admin")
      redirect_to debug_session_admin_platform_evolution_path(session), notice: "Session marked as failed"
    end

    # GET /admin/platform_evolution/code_fixes
    def code_fixes
      @fixes = CodeFix.includes(:support_ticket, :debug_session).order(created_at: :desc)
      @fixes = @fixes.where(status: params[:status]) if params[:status].present?
      @fixes = @fixes.page(params[:page]).per(30)
    end

    # GET /admin/platform_evolution/code_fix/:id
    def show_code_fix
      @fix = CodeFix.find(params[:id])
      @session = @fix.debug_session
      @ticket = @fix.support_ticket
      @prs = @fix.pull_request_submissions.order(created_at: :desc)
    end

    # POST /admin/platform_evolution/code_fix/:id/approve
    def approve_fix
      @fix = CodeFix.find(params[:id])
      @fix.approve!(reviewer: current_admin.email, notes: params[:notes])

      # Auto-create PR if approved
      if params[:create_pr] == 'true'
        PlatformEvolution::PullRequestJob.perform_later(@fix.id)
        redirect_to admin_platform_evolution_code_fix_path(@fix), notice: "Fix approved and PR creation started"
      else
        redirect_to admin_platform_evolution_code_fix_path(@fix), notice: "Fix approved"
      end
    end

    # POST /admin/platform_evolution/code_fix/:id/reject
    def reject_fix
      @fix = CodeFix.find(params[:id])
      @fix.reject!(reviewer: current_admin.email, notes: params[:notes])
      redirect_to admin_platform_evolution_code_fix_path(@fix), notice: "Fix rejected"
    end

    # GET /admin/platform_evolution/pull_requests
    def pull_requests
      @prs = PullRequestSubmission.includes(:code_fix, :support_ticket).order(created_at: :desc)
      @prs = @prs.where(status: params[:status]) if params[:status].present?
      @prs = @prs.page(params[:page]).per(30)
    end

    # GET /admin/platform_evolution/pull_request/:id
    def show_pull_request
      @pr = PullRequestSubmission.find(params[:id])
      @fix = @pr.code_fix
      @ticket = @pr.support_ticket
    end

    # POST /admin/platform_evolution/pull_request/:id/merge
    def merge_pr
      @pr = PullRequestSubmission.find(params[:id])

      # In production, this would trigger the actual GitHub merge
      # For now, we'll simulate it
      @pr.merge!(
        merged_by: current_admin.email,
        merge_commit_sha: SecureRandom.hex(20)
      )

      redirect_to admin_platform_evolution_pull_request_path(@pr), notice: "PR merged and fix applied"
    end

    # GET /admin/platform_evolution/error_logs
    def error_logs
      @entries = ErrorLogEntry.order(occurred_at: :desc)
      @entries = @entries.unprocessed if params[:unprocessed] == 'true'
      @entries = @entries.page(params[:page]).per(50)

      @grouped_errors = ErrorLogEntry.grouped_by_signature(since: 24.hours.ago)
    end

    # POST /admin/platform_evolution/run_log_scan
    def run_log_scan
      entity = Entity.find(params[:entity_id]) if params[:entity_id]
      PlatformEvolution::LogMonitorJob.perform_later(entity&.id)
      redirect_to admin_platform_evolution_path, notice: "Log scan started"
    end

    # GET /admin/platform_evolution/feature_requests
    def feature_requests
      @pending_features = SupportTicket.feature_requests.awaiting_approval.order(created_at: :desc)
      @approved_features = SupportTicket.approved_features.open_tickets.order(created_at: :desc)
      @rejected_features = SupportTicket.feature_requests.where(status: 'wont_fix').order(updated_at: :desc).limit(20)
    end

    # POST /admin/platform_evolution/ticket/:id/approve_feature
    def approve_feature
      @ticket = SupportTicket.find(params[:id])
      
      unless @ticket.is_feature_request?
        redirect_to ticket_admin_platform_evolution_path(@ticket), alert: "Not a feature request"
        return
      end

      @ticket.approve_feature!(approved_by: current_admin)
      
      # Optionally start the debug/build process
      if params[:start_work] == 'true'
        PlatformEvolution::DebugAgentJob.perform_later(@ticket.id)
        redirect_to ticket_admin_platform_evolution_path(@ticket), notice: "Feature approved and work started"
      else
        redirect_to ticket_admin_platform_evolution_path(@ticket), notice: "Feature approved for development"
      end
    end

    # POST /admin/platform_evolution/ticket/:id/reject_feature
    def reject_feature
      @ticket = SupportTicket.find(params[:id])
      
      unless @ticket.is_feature_request?
        redirect_to ticket_admin_platform_evolution_path(@ticket), alert: "Not a feature request"
        return
      end

      @ticket.reject_feature!(
        reason: params[:reason] || "Feature request declined",
        rejected_by: current_admin
      )
      
      redirect_to feature_requests_admin_platform_evolution_path, notice: "Feature request rejected"
    end

    private

    def set_ticket
      @ticket = SupportTicket.find(params[:id])
    end

    def calculate_stats
      {
        total_tickets: SupportTicket.count,
        open_tickets: SupportTicket.open_tickets.count,
        critical_tickets: SupportTicket.critical.open_tickets.count,
        tickets_today: SupportTicket.where('created_at > ?', 24.hours.ago).count,
        avg_resolution_time: SupportTicket.resolved.where.not(time_to_resolution_minutes: nil).average(:time_to_resolution_minutes)&.round || 0,
        pending_fixes: CodeFix.validated.count,
        pending_prs: PullRequestSubmission.pending_review.count,
        merged_this_week: PullRequestSubmission.merged.where('merged_at > ?', 7.days.ago).count,
        auto_fixed_rate: calculate_auto_fix_rate
      }
    end

    def calculate_auto_fix_rate
      total_resolved = SupportTicket.where('resolved_at > ?', 30.days.ago).count
      return 0 if total_resolved.zero?

      auto_fixed = SupportTicket.where('resolved_at > ?', 30.days.ago)
        .where(source: %w[log_monitor amos_detected agent_failure])
        .joins(:pull_request_submissions)
        .where(pull_request_submissions: { status: 'merged' })
        .count

      ((auto_fixed.to_f / total_resolved) * 100).round(1)
    end
  end
end

