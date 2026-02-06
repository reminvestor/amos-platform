# frozen_string_literal: true

module Api
  module V1
    # ExternalAgentsController - API for AI agents from external platforms
    #
    # Enables OpenClaw, custom agents, and other external AI systems to:
    # - Register and declare capabilities
    # - Discover and claim bounties
    # - Execute platform tools
    # - Submit completed work
    # - Earn tokens for their operators
    #
    class ExternalAgentsController < Api::V1::BaseController
      # Skip standard auth for agent-specific endpoints that use agent API key
      skip_before_action :authenticate_api_user!, only: [:bounties, :claim_bounty, :execute_tool, :submit_work, :status, :execution_status, :notifications, :notification_action, :recommended_bounties, :platform_info, :available_tools, :bounty_types, :configure_webhook]
      skip_before_action :require_entity!, only: [:bounties, :claim_bounty, :execute_tool, :submit_work, :status, :execution_status, :notifications, :notification_action, :recommended_bounties, :platform_info, :available_tools, :bounty_types, :configure_webhook]
      
      before_action :authenticate_external_agent!, only: [:bounties, :claim_bounty, :execute_tool, :submit_work, :status, :execution_status, :notifications, :notification_action, :recommended_bounties, :platform_info, :available_tools, :bounty_types, :configure_webhook]
      before_action :set_bounty, only: [:claim_bounty, :submit_work]
      before_action :set_execution, only: [:execute_tool, :submit_work, :execution_status]

      # ═══════════════════════════════════════════════════════════════════════
      # REGISTRATION (uses operator API key)
      # ═══════════════════════════════════════════════════════════════════════

      # POST /api/v1/external_agents/register
      # Register a new external agent
      # Optional webhook config: { webhook_url: "https://...", webhook_events: ["bounty.recommended", "execution.approved"] }
      def register
        service = ExternalAgentService.new(user: current_user, entity: current_entity)
        result = service.register_agent(
          agent_identifier: params[:agent_identifier],
          agent_name: params[:agent_name],
          agent_platform: params[:agent_platform] || 'openclaw',
          capabilities: params[:capabilities] || {},
          metadata: params[:metadata] || {}
        )

        if result[:success]
          # Configure webhook if provided
          if params[:webhook_url].present?
            result[:agent].configure_webhook!(
              url: params[:webhook_url],
              secret: params[:webhook_secret],
              events: params[:webhook_events] || []
            )
          end

          render json: {
            success: true,
            agent: result[:agent].to_api_response(include_key: true),
            webhook: result[:agent].webhook_url.present? ? {
              url: result[:agent].webhook_url,
              secret: result[:agent].webhook_secret,
              events: result[:agent].webhook_events
            } : nil,
            message: result[:message]
          }, status: :created
        else
          render json: {
            success: false,
            error: result[:error]
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/external_agents
      # List operator's registered agents
      def index
        agents = current_user.external_agent_registrations
                             .includes(:entity)
                             .order(created_at: :desc)

        render json: {
          success: true,
          agents: agents.map { |a| a.to_api_response },
          count: agents.count
        }
      end

      # DELETE /api/v1/external_agents/:id
      # Revoke an agent registration
      def destroy
        agent = current_user.external_agent_registrations.find(params[:id])
        agent.revoke!

        render json: {
          success: true,
          message: "Agent '#{agent.agent_name}' has been revoked"
        }
      end

      # ═══════════════════════════════════════════════════════════════════════
      # AGENT OPERATIONS (uses external agent API key)
      # ═══════════════════════════════════════════════════════════════════════

      # GET /api/v1/external_agents/bounties
      # Discover available bounties matching agent's capabilities
      def bounties
        service = ExternalAgentService.new(agent: @current_agent)
        result = service.discover_bounties(
          type: params[:type],
          min_points: params[:min_points]&.to_i,
          max_points: params[:max_points]&.to_i,
          limit: params[:limit]&.to_i || 20
        )

        render json: {
          success: true,
          bounties: result[:bounties],
          meta: result[:meta]
        }
      end

      # POST /api/v1/external_agents/bounties/:bounty_id/claim
      # Claim a bounty
      def claim_bounty
        service = ExternalAgentService.new(agent: @current_agent)
        result = service.claim_bounty(
          bounty: @bounty,
          approach: params[:approach],
          estimated_completion: params[:estimated_completion]
        )

        if result[:success]
          render json: {
            success: true,
            execution: result[:execution].to_api_response,
            message: result[:message]
          }, status: :created
        else
          render json: {
            success: false,
            error: result[:error]
          }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/external_agents/tools/:tool_name/execute
      # Execute a platform tool
      def execute_tool
        tool_name = params[:tool_name]
        
        unless @execution.can_execute_tool?(tool_name)
          return render json: {
            success: false,
            error: "Cannot execute tool '#{tool_name}': #{tool_denied_reason(tool_name)}"
          }, status: :forbidden
        end

        service = ExternalAgentService.new(agent: @current_agent)
        result = service.execute_tool(
          execution: @execution,
          tool_name: tool_name,
          args: params[:args] || {}
        )

        if result[:success]
          render json: {
            success: true,
            tool: tool_name,
            result: result[:tool_result],
            execution_log: {
              tool_calls_remaining: @execution.tool_calls_remaining,
              time_remaining: @execution.time_remaining_formatted
            }
          }
        else
          render json: {
            success: false,
            error: result[:error]
          }, status: result[:status] || :unprocessable_entity
        end
      end

      # POST /api/v1/external_agents/bounties/:bounty_id/submit
      # Submit completed work
      def submit_work
        service = ExternalAgentService.new(agent: @current_agent)
        result = service.submit_work(
          execution: @execution,
          work_summary: params[:work_summary],
          deliverables: params[:deliverables],
          work_log: params[:work_log]
        )

        if result[:success]
          render json: {
            success: true,
            submission: {
              id: @execution.id,
              status: @execution.status,
              ai_review_eta: '5 minutes'
            },
            message: result[:message]
          }
        else
          render json: {
            success: false,
            error: result[:error]
          }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/external_agents/status
      # Get agent status, earnings, and current work
      def status
        render json: @current_agent.status_summary
      end

      # GET /api/v1/external_agents/executions/:id
      # Get execution status
      def execution_status
        render json: {
          success: true,
          execution: @execution.to_api_response
        }
      end

      # ═══════════════════════════════════════════════════════════════════════
      # NOTIFICATIONS (AMOS recommendations)
      # ═══════════════════════════════════════════════════════════════════════

      # GET /api/v1/external_agents/notifications
      # Get notifications from AMOS (bounty recommendations, trust updates, etc.)
      def notifications
        notifications = @current_agent.external_agent_notifications
                                      .unread
                                      .order(created_at: :desc)
                                      .limit(params[:limit]&.to_i || 20)

        # Mark as read unless ?mark_read=false
        unless params[:mark_read] == 'false'
          notifications.each(&:mark_read!)
        end

        render json: {
          success: true,
          notifications: notifications.map(&:to_api_response),
          unread_count: @current_agent.external_agent_notifications.unread.count,
          recommendations: notifications.count { |n| n.notification_type == 'bounty_recommendation' }
        }
      end

      # POST /api/v1/external_agents/notifications/:id/action
      # Record action on a notification (claim, dismiss, etc.)
      def notification_action
        notification = @current_agent.external_agent_notifications.find(params[:id])
        action = params[:action_type]

        unless ExternalAgentNotification::ACTION_TYPES.include?(action)
          return render json: { 
            success: false, 
            error: "Invalid action. Valid: #{ExternalAgentNotification::ACTION_TYPES.join(', ')}" 
          }, status: :unprocessable_entity
        end

        notification.record_action!(action)

        render json: {
          success: true,
          notification: notification.to_api_response,
          message: "Action '#{action}' recorded"
        }
      end

      # GET /api/v1/external_agents/recommended_bounties
      # Get bounties AMOS recommends for this agent
      def recommended_bounties
        matching_service = ExternalAgentMatchingService.new(@current_entity)
        matches = matching_service.find_bounties_for_agent(@current_agent, limit: params[:limit]&.to_i || 10)

        render json: {
          success: true,
          recommendations: matches,
          agent_capabilities: @current_agent.capabilities.keys,
          note: "These bounties are matched to your declared capabilities and trust level"
        }
      end

      # ═══════════════════════════════════════════════════════════════════════
      # PLATFORM INFO (for agent context)
      # ═══════════════════════════════════════════════════════════════════════

      # GET /api/v1/external_agents/platform_info
      # Get platform capabilities for agent context
      def platform_info
        capabilities = PlatformCapabilitiesService.external_agent_capabilities(
          entity: @current_entity,
          agent: @current_agent
        )

        render json: {
          success: true,
          platform: capabilities
        }
      end

      # GET /api/v1/external_agents/available_tools
      # Get tools this agent can use
      def available_tools
        tools = PlatformCapabilitiesService.available_tools(
          entity: @current_entity,
          for_external_agents: true,
          agent: @current_agent
        )

        render json: {
          success: true,
          tools: tools[:tools],
          total: tools[:total_count],
          categories: tools[:categories],
          note: "Tools available to your agent based on trust level and allowed list"
        }
      end

      # POST /api/v1/external_agents/webhook
      # Configure webhook for real-time notifications
      def configure_webhook
        if params[:webhook_url].present?
          @current_agent.configure_webhook!(
            url: params[:webhook_url],
            secret: params[:webhook_secret],
            events: params[:webhook_events] || []
          )

          render json: {
            success: true,
            webhook: {
              url: @current_agent.webhook_url,
              secret: @current_agent.webhook_secret,
              events: @current_agent.webhook_events.presence || ['*'],
              supported_events: ExternalAgentWebhookService::EVENT_TYPES
            },
            message: "Webhook configured. You will receive POST requests for #{@current_agent.webhook_events.presence&.join(', ') || 'all events'}."
          }
        else
          # Disable webhook
          @current_agent.update!(webhook_url: nil, webhook_secret: nil, webhook_events: [])

          render json: {
            success: true,
            message: "Webhook disabled."
          }
        end
      end

      # GET /api/v1/external_agents/bounty_types
      # Get available bounty types and descriptions
      def bounty_types
        types = PlatformCapabilitiesService.bounty_types

        # Filter to agent's allowed types if applicable
        if @current_agent.allowed_bounty_types.present?
          types = types.select { |t| @current_agent.allowed_bounty_types.include?(t[:type]) }
        end

        render json: {
          success: true,
          bounty_types: types,
          agent_allowed_types: @current_agent.allowed_bounty_types,
          trust_level: @current_agent.trust_level
        }
      end

      private

      def authenticate_external_agent!
        auth_header = request.headers['Authorization']
        token = auth_header&.gsub(/^Bearer /, '')

        unless token.present?
          return render json: { 
            success: false, 
            error: 'Authorization token required' 
          }, status: :unauthorized
        end

        @current_agent = ExternalAgentRegistration.authenticate(token)

        unless @current_agent
          return render json: { 
            success: false, 
            error: 'Invalid or inactive agent API key' 
          }, status: :unauthorized
        end

        unless @current_agent.active?
          return render json: { 
            success: false, 
            error: "Agent is #{@current_agent.status}: #{@current_agent.suspension_reason}" 
          }, status: :forbidden
        end

        # Set entity context for downstream operations
        @current_entity = @current_agent.entity
        @current_user = @current_agent.operator
      end

      def set_bounty
        @bounty = Bounty.find(params[:bounty_id] || params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'Bounty not found' }, status: :not_found
      end

      def set_execution
        if params[:execution_id].present?
          @execution = @current_agent.external_agent_executions.find(params[:execution_id])
        elsif @bounty.present?
          @execution = @current_agent.external_agent_executions.find_by!(bounty: @bounty)
        elsif params[:id].present?
          @execution = @current_agent.external_agent_executions.find(params[:id])
        end
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'Execution not found' }, status: :not_found
      end

      def tool_denied_reason(tool_name)
        return "execution expired" if @execution.expired?
        return "execution not in progress" unless @execution.status == 'in_progress'
        return "tool not in allowed list" unless @current_agent.can_use_tool?(tool_name)
        return "tool call limit reached" if @execution.tool_calls_count >= @current_agent.tool_calls_per_bounty
        "unknown"
      end
    end
  end
end
