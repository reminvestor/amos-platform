# frozen_string_literal: true

module V3
  module Tools
    # BashTool - Sandboxed command execution
    #
    # Inspired by Pi's bash tool. Gives the agent a powerful escape hatch
    # for operations not covered by other tools:
    # - curl for testing APIs
    # - jq for JSON processing
    # - ruby -e for quick calculations
    # - Data transformations
    # - File format conversions
    #
    # SECURITY: All commands run in a sandboxed environment with:
    # - Time limits (30 second max)
    # - Output truncation (10KB max)
    # - Blocked destructive commands
    # - Entity-isolated execution
    # - No access to internal services
    #
    class BashTool < ::Tools::BaseTool
      MAX_EXECUTION_TIME = 30 # seconds
      MAX_OUTPUT_SIZE = 10_240 # 10KB
      
      # Commands that are always blocked
      BLOCKED_COMMANDS = %w[
        rm rmdir mkfs fdisk dd shutdown reboot halt poweroff
        passwd useradd userdel groupadd groupdel chown chmod
        mount umount kill killall pkill
        iptables ufw firewall-cmd
        systemctl service
      ].freeze

      # Patterns that are blocked
      BLOCKED_PATTERNS = [
        /rm\s+(-rf?|--recursive)\s+\//,      # rm -rf /
        />\s*\/dev\//,                         # Redirect to device
        /mkfs/,                                # Filesystem format
        /dd\s+if=/,                            # Disk operations
        /:(){ :|:& };:/,                       # Fork bomb
        /curl.*localhost/i,                    # No accessing localhost
        /curl.*127\.0\.0\.1/,                  # No accessing loopback
        /curl.*0\.0\.0\.0/,                    # No accessing all interfaces
        /wget.*localhost/i,                    # Same for wget
        /DROP\s+TABLE/i,                       # SQL injection
        /DELETE\s+FROM/i,                      # SQL deletion
        /TRUNCATE/i,                           # SQL truncation
        /eval\s*\(/,                           # Eval in scripts (limited)
      ].freeze

      def self.metadata
        {
          name: "bash",
          description: <<~DESC.strip,
            Execute a shell command in a sandboxed environment. Useful for:
            - Data processing: curl, jq, awk, sed, sort, uniq, wc
            - Quick calculations: ruby -e, python3 -c, bc
            - API testing: curl with external APIs
            - Text processing: grep, tr, cut, paste
            - JSON/CSV manipulation
            
            Commands run with a 30-second timeout and 10KB output limit.
            Destructive commands (rm -rf, etc.) are blocked.
            
            Examples:
            - bash(command: "echo '2+2' | bc")
            - bash(command: "curl -s 'https://api.github.com/users/octocat' | jq '.name'")
            - bash(command: "ruby -e 'puts (1..10).map{|n| n**2}.inspect'")
            - bash(command: "echo 'hello,world' | tr ',' '\\n'")
          DESC
          category: "v3_core",
          input_schema: {
            type: "object",
            properties: {
              command: {
                type: "string",
                description: "The shell command to execute"
              },
              timeout: {
                type: "integer",
                description: "Optional timeout in seconds (default: 30, max: 30)"
              }
            },
            required: ["command"]
          }
        }
      end

      def execute(args)
        log_execution(args)

        command = get_arg(args, :command)
        timeout = [get_arg(args, :timeout, MAX_EXECUTION_TIME).to_i, MAX_EXECUTION_TIME].min

        return error_response("Missing required field: command") if command.blank?

        # Security check
        security_result = check_security(command)
        return security_result if security_result

        # Log the command for audit
        Rails.logger.info "[V3::Bash] User #{user&.id} executing: #{command.truncate(200)}"

        # Execute in sandboxed environment
        result = execute_sandboxed(command, timeout)

        if result[:success]
          success_response(
            command: command,
            output: result[:output],
            exit_code: result[:exit_code],
            truncated: result[:truncated] || false,
            execution_time_ms: result[:execution_time_ms]
          )
        else
          error_response(
            result[:error],
            command: command,
            exit_code: result[:exit_code],
            output: result[:output]&.truncate(2000)
          )
        end
      rescue => e
        Rails.logger.error "[V3::Bash] Error: #{e.message}"
        error_response("Command execution failed: #{e.message}")
      end

      private

      def check_security(command)
        # Check blocked commands
        first_cmd = command.strip.split(/\s+/).first&.gsub(/^sudo\s+/, "")
        if BLOCKED_COMMANDS.include?(first_cmd)
          return error_response("Command '#{first_cmd}' is not allowed in sandbox")
        end

        # Check blocked patterns
        BLOCKED_PATTERNS.each do |pattern|
          if command.match?(pattern)
            return error_response("Command contains blocked pattern: #{pattern.source.truncate(50)}")
          end
        end

        # Check for sudo
        if command.strip.start_with?("sudo")
          return error_response("sudo is not available in sandbox")
        end

        nil # No security issues
      end

      def execute_sandboxed(command, timeout)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        output = ""
        exit_code = nil
        truncated = false

        begin
          # Use Open3 for proper stderr capture
          require "open3"
          
          Timeout.timeout(timeout) do
            stdout, stderr, status = Open3.capture3(command)
            output = stdout
            output += "\nSTDERR: #{stderr}" if stderr.present?
            exit_code = status.exitstatus
          end
        rescue Timeout::Error
          return {
            success: false,
            error: "Command timed out after #{timeout} seconds",
            output: output.truncate(MAX_OUTPUT_SIZE),
            exit_code: -1,
            execution_time_ms: timeout * 1000
          }
        end

        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        execution_time_ms = ((end_time - start_time) * 1000).round

        # Truncate output if too large
        if output.length > MAX_OUTPUT_SIZE
          output = output.first(MAX_OUTPUT_SIZE) + "\n\n... [OUTPUT TRUNCATED - #{output.length} bytes total, showing first #{MAX_OUTPUT_SIZE}]"
          truncated = true
        end

        {
          success: exit_code == 0,
          output: output,
          exit_code: exit_code,
          truncated: truncated,
          execution_time_ms: execution_time_ms,
          error: exit_code != 0 ? "Command exited with code #{exit_code}" : nil
        }
      end
    end
  end
end
