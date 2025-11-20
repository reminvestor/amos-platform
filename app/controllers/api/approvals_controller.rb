class Api::ApprovalsController < Api::BaseController
  # MCP Approval Client endpoints
  # These are used by the Claude Code MCP server for approval workflows

  # No need to skip CSRF - Api::BaseController already handles it
  # No need to skip authentication - Api::BaseController already handles it

  # POST /api/request-approval
  # Handles approval requests from MCP client
  def request_approval
    # Log the approval request for debugging
    Rails.logger.info "📝 Approval request received: #{params.inspect}"

    # For now, auto-approve all requests in development
    # In production, you'd integrate with a proper approval system
    render json: {
      approved: true,
      message: "Auto-approved in #{Rails.env}",
      request_id: SecureRandom.uuid
    }, status: :ok
  end

  # POST /api/get_instructions
  # Returns any pending instructions from the user
  def get_instructions
    # No pending instructions for now
    render json: {
      instructions: nil,
      has_instructions: false
    }, status: :ok
  end
end
