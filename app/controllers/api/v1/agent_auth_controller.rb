module Api
  module V1
    class AgentAuthController < Api::BaseController
      # authenticate_user! is already skipped in Api::BaseController (via ApplicationController logic or skip_before_action)
      # We don't need to skip it again, which causes errors if it's not in the chain.
      
      def heartbeat
        # Log heartbeat for agent execution ID
        execution_id = params[:id]
        Rails.logger.info "💓 Heartbeat received for Agent Execution #{execution_id}"
        
        # Optional: Update execution record if it exists
        if defined?(AgentPluginExecution)
          execution = AgentPluginExecution.find_by(id: execution_id)
          if execution
            # execution.touch(:last_heartbeat_at) if execution.respond_to?(:last_heartbeat_at)
            Rails.logger.debug "   - Execution found: #{execution.status}"
          end
        end

        head :ok
      end

      def current_task
        execution_id = params[:id]
        Rails.logger.info "📋 Current task requested for Agent Execution #{execution_id}"
        
        response_data = { 
          status: "idle", 
          message: "No pending tasks" 
        }

        if defined?(AgentPluginExecution)
          execution = AgentPluginExecution.find_by(id: execution_id)
          if execution
            response_data[:status] = execution.status
            response_data[:task] = execution.input_params # or equivalent
          end
        end
        
        render json: response_data
      end
    end
  end
end

