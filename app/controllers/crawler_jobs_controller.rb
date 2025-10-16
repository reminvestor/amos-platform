require "open3"
require "timeout"

class CrawlerJobsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_entity
  before_action :set_crawler_job, only: [ :show, :execute, :test, :logs, :debug, :improve, :fix_bugs, :chat, :reset_conversation ]

  def index
    @crawler_jobs = @entity.crawler_jobs.order(created_at: :desc)
  end

  def show
    # @crawler_job is set by before_action

    # Initialize conversation if needed - but with intelligent questions
    if @crawler_job.crawler_conversations.empty?
      # Set an initial greeting
      @crawler_job.add_message("assistant", "Hello! I'll help you create a crawler to collect contact information based on your description. Let me ask a few questions to get started.")
      @crawler_job.update(conversation_stage: "analyzing") # Start in analyzing mode

      # Use the conversation handler to generate the first set of questions
      # based on the initial description
      if @crawler_job.description.present?
        conversation_handler = ConversationHandlerService.new(@crawler_job)
        # Send a system message to trigger the first round of questions
        conversation_handler.generate_initial_questions(@crawler_job.description)
      end
    end
  end

  def new
    @crawler_job = @entity.crawler_jobs.new
  end

  def create
    @crawler_job = @entity.crawler_jobs.new(crawler_job_params)
    @crawler_job.user = current_user
    @crawler_job.status = "pending" # Initial status

    if @crawler_job.save
      # Redirect to the show page where the chat interface is
      flash[:notice] = "Crawler job created. Start describing what you want to crawl in the chat."
      redirect_to crawler_job_path(@crawler_job)
    else
      flash.now[:alert] = "Failed to create crawler job."
      render :new, status: :unprocessable_entity
    end
  end

  # POST /crawler_jobs/:id/chat
  def chat
    # Processing a message in the chat
    return head :bad_request unless params[:message].present?

    # Don't process if the job is currently in a busy state
    busy_statuses = [ "generating", "testing", "improving", "fixing" ]
    if busy_statuses.include?(@crawler_job.status)
      render json: { error: "Cannot process messages while the crawler is being #{@crawler_job.status}" }, status: :unprocessable_entity
      return
    end

    begin
      # Process the message and get a response
      conversation_handler = ConversationHandlerService.new(@crawler_job)
      response = conversation_handler.handle_message(params[:message])

      # Check if we're starting generation (indicated by status change)
      generating = @crawler_job.reload.status == "generating"

      # Return the response and status
      render json: { response: response, generating: generating }
    rescue => e
      # Log the error
      Rails.logger.error("Error in chat action: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))

      # Add error to crawler job logs
      @crawler_job.add_log("Chat error: #{e.message}", "error")

      # Return a friendlier error message to the client
      render json: {
        response: "Sorry, I encountered an error while processing your message. Please try again or use different wording.",
        error: "An error occurred while processing your request."
      }, status: :ok
    end
  end

  # POST /crawler_jobs/:id/reset_conversation
  def reset_conversation
    @crawler_job.reset_conversation

    # If the crawler is in a 'ready' or 'failed' state, reset it for a new conversation
    if [ "ready", "failed" ].include?(@crawler_job.status)
      @crawler_job.update(
        conversation_stage: "analyzing",
        target_urls: nil,
        test_results: nil,
        improvement_attempts: nil
      )
    end

    # Set an initial assistant message
    @crawler_job.add_message("assistant", "Hello! I'm your crawler assistant. Please describe what kind of contact information you want to collect and from which websites.")

    # Return success
    head :ok
  end

  # POST /crawler_jobs/:id/execute
  def execute
    # @crawler_job is set by before_action
    if @crawler_job.status == "ready" && @crawler_job.generated_code.present?
      ExecuteCrawlerJob.perform_later(@crawler_job.id)
      flash[:notice] = "Crawler execution has been queued."
    else
      flash[:alert] = "Crawler job is not ready for execution or has no code."
    end
    redirect_to crawler_job_path(@crawler_job)
  end

  # POST /crawler_jobs/:id/test
  def test
    # @crawler_job is set by before_action
    if @crawler_job.status == "ready" && @crawler_job.generated_code.present?
      # Enqueue the TestCrawlerJob
      TestCrawlerJob.perform_later(@crawler_job.id)
      flash[:notice] = "Crawler test run has been queued. Check Heroku dyno logs (run.XXXX) for output."
    else
      flash[:alert] = "Crawler job is not ready for testing or has no code."
    end
    redirect_to crawler_job_path(@crawler_job)
  end

  # GET /crawler_jobs/:id/logs
  # AJAX endpoint for polling new logs
  def logs
    since_id = params[:since].to_i
    @logs = @crawler_job.crawler_job_logs.where("id > ?", since_id)

    render json: {
      logs: @logs.as_json(only: [ :id, :message, :log_level, :timestamp ]),
      job_status: @crawler_job.status,
      job_status_class: helpers.status_badge_class(@crawler_job.status)
    }
  end

  # POST /crawler_jobs/:id/debug
  def debug
    # @crawler_job is set by before_action
    if @crawler_job.status == "ready" && @crawler_job.generated_code.present?
      # Run the Python script locally and capture the output
      output = nil
      error = nil
      exit_status = nil

      Tempfile.create([ "debug_crawler_#{@crawler_job.id}_", ".py" ]) do |file|
        file.write(@crawler_job.generated_code)
        file.flush

        # Rather than using Timeout which can lead to thread issues,
        # we'll use the Open3.popen3 method with a separate thread
        # for monitoring timeout
        begin
          # Build the command with environment variables
          env = { "MARKETING_API_KEY" => current_user.api_key, "CRAWLER_TEST_MODE" => "true" }
          cmd = "python3 #{file.path}"

          # Log the first 20 lines of code for debugging
          @crawler_job.add_log("Debug execution starting with the first 20 lines of Python code:", "debug")
          @crawler_job.add_log(@crawler_job.generated_code.lines.take(20).join, "debug")

          # Use a mutex and condition variable for thread synchronization
          mutex = Mutex.new
          resource = ConditionVariable.new
          timeout_reached = false
          cmd_completed = false

          # For partial output collection in case of timeout
          partial_output = []
          partial_error = []

          # Start the command in a separate thread
          thread = Thread.new do
            Open3.popen3(env, cmd) do |stdin, stdout, stderr, wait_thr|
              # Use non-blocking reads with a buffer to collect partial output
              stdout_reader = Thread.new do
                while line = stdout.gets
                  mutex.synchronize { partial_output << line.strip }
                end
              end

              stderr_reader = Thread.new do
                while line = stderr.gets
                  mutex.synchronize { partial_error << line.strip }
                end
              end

              # Wait for the process to complete
              status = wait_thr.value
              stdout_reader.join(2)
              stderr_reader.join(2)

              # Get full output
              mutex.synchronize do
                unless timeout_reached
                  output = partial_output.join("\n")
                  error = partial_error.join("\n")
                  exit_status = status.exitstatus
                  cmd_completed = true
                  resource.signal
                end
              end
            end
          end

          # Wait for either completion or timeout
          mutex.synchronize do
            # Increase timeout to 60 seconds
            if !resource.wait(mutex, 60) && !cmd_completed
              timeout_reached = true
              # Use partial output collected so far
              output = partial_output.empty? ? "Command timed out after 60 seconds (no output)" : partial_output.join("\n")
              error = partial_error.empty? ? "Execution exceeded 60 second timeout" : partial_error.join("\n")
              exit_status = -1

              # Try to kill the thread gracefully
              thread.kill if thread.alive?
            end
          end

          # Wait for thread to finish (it should be done already)
          thread.join(5)
        rescue => e
          output = ""
          error = "Error executing command: #{e.message}"
          exit_status = -1
        end
      end

      # Save the output as logs
      if output.present?
        output.each_line do |line|
          line = line.strip
          next if line.blank?
          @crawler_job.add_log(line, "debug")
        end
      end

      # Track if we had any errors
      has_errors = false

      if error.present? && error != ""
        has_errors = true
        error.each_line do |line|
          line = line.strip
          next if line.blank?
          @crawler_job.add_log("ERROR: #{line}", "error")
        end
      end

      # Also consider exit status
      has_errors = true if exit_status != 0

      # Always log the final status
      @crawler_job.add_log("Debug execution completed with exit status: #{exit_status}", exit_status == 0 ? "info" : "error")

      # Check for auto_fix parameter
      auto_fix = params[:auto_fix] == "true"

      # Automatically trigger bug fixing if requested and errors were found
      if auto_fix && has_errors
        flash[:notice] = "Debug execution completed with errors. Automatically starting bug fixing..."
        # Save the redirect and hand off to fix_bugs
        fix_bugs
        return
      end

      flash[:notice] = "Debug execution completed. See logs for details."
    else
      flash[:alert] = "Crawler job is not ready for debugging or has no code."
    end

    redirect_to crawler_job_path(@crawler_job)
  end

  # POST /crawler_jobs/:id/improve
  def improve
    # @crawler_job is set by before_action
    if @crawler_job.status == "ready" || @crawler_job.status == "failed"
      # Queue job to improve the code
      ImproveGeneratedCodeJob.perform_later(@crawler_job.id)
      @crawler_job.update(status: "improving")
      flash[:notice] = "Code improvement has been queued. LLM will fix common issues in the generated code."
    else
      flash[:alert] = "Crawler job must be in 'ready' or 'failed' state to improve the code."
    end

    redirect_to crawler_job_path(@crawler_job)
  end

  # POST /crawler_jobs/:id/fix_bugs
  def fix_bugs
    # @crawler_job is set by before_action
    if @crawler_job.status == "ready" || @crawler_job.status == "failed"
      # Use the BugFixService to fix runtime issues
      bug_fix_service = BugFixService.new(@crawler_job)
      bug_fix_service.fix_runtime_bugs

      flash[:notice] = "Runtime bug fixing has been started. Check logs for updates."
    else
      flash[:alert] = "Crawler job must be in 'ready' or 'failed' state to fix runtime bugs."
    end

    redirect_to crawler_job_path(@crawler_job)
  end

  private

  def set_entity
    @entity = current_entity
    unless @entity
      flash[:alert] = "Please select an entity first."
      redirect_to entities_path
    end
  end

  def set_crawler_job
    @crawler_job = @entity.crawler_jobs.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = "Crawler job not found."
    redirect_to crawler_jobs_path
  end

  def crawler_job_params
    params.require(:crawler_job).permit(:description)
  end
end
