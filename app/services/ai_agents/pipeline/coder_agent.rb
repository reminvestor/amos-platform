module AiAgents::Pipeline
  class CoderAgent < BaseAgent
    # 11-Step Workflow Implementation
    # Based on AI_PIPELINE_HOW_IT_WORKS.md lines 93-115
    def execute!
      log("Starting CoderAgent - 11-step workflow")

      inputs = agent_execution.inputs
      plan_artifact = get_artifact('plan')
      plan = plan_artifact&.get_content || plan_artifact&.content

      # Get connections
      git_connection = pipeline_execution.git_connection
      raise "No GitHub connection configured" unless git_connection

      github_client = Git::GithubClient.new(git_connection)
      repository = "#{git_connection.config[:organization]}/#{git_connection.config[:repository]}"

      # STEP 1: Create isolated workspace (0700 permissions)
      log("[1/11] Creating isolated workspace")
      workspace = workspace_manager.create_workspace!
      agent_execution.update!(workspace_path: workspace)
      log("Workspace created: #{workspace}")

      # STEP 2: Clone repository (using git command in workspace)
      log("[2/11] Cloning repository: #{repository}")
      clone_repository_to_workspace(repository, git_connection.config[:token])

      # STEP 3: Create feature branch: pipeline/{ticket_id}-{timestamp}
      log("[3/11] Creating feature branch")
      branch_name = "pipeline/#{pipeline_execution.ticket_id.parameterize}-#{Time.now.to_i}"

      branch_result = github_client.create_branch(repository, branch_name, from_branch: 'main')
      raise "Failed to create branch: #{branch_result[:error]}" unless branch_result[:success]

      log("Branch created: #{branch_name}")

      # STEP 4: Read implementation plan
      log("[4/11] Reading implementation plan")
      unless plan
        raise "No plan found. PlannerAgent must run first."
      end
      log("Plan loaded (#{plan.bytesize} bytes)")

      # STEP 5: Generate code based on plan
      log("[5/11] Generating code with Claude Sonnet 4.5")
      code_result = generate_code_with_claude(plan, inputs)

      unless code_result[:success]
        raise "Code generation failed: #{code_result[:error]}"
      end

      generated_files = code_result[:files]
      log("Generated #{generated_files.length} files")

      # STEP 6: Write files to workspace (prepare for push)
      log("[6/11] Preparing files for push")
      save_artifact('code', 'generated_code.json', generated_files.to_json)

      # STEP 7: Create/update tests (included in generated files)
      log("[7/11] Tests included in generated files")
      test_files = generated_files.select { |f| f[:path].include?('test') || f[:path].include?('spec') }
      log("Test files: #{test_files.length}")

      # STEP 8 & 9: Commit changes and push branch to remote (MCP push_files does both)
      log("[8-9/11] Pushing files to branch: #{branch_name}")
      commit_message = build_commit_message(inputs['ticket_title'], inputs['ticket_id'])

      push_result = github_client.push_files(
        repository,
        branch_name,
        generated_files.map { |f| { path: f[:path], content: f[:content] } },
        commit_message
      )

      unless push_result[:success]
        raise "Failed to push files: #{push_result[:error]}"
      end

      log("Files pushed successfully (commit: #{push_result[:commit_sha]})")

      # STEP 10: Create Pull Request via GitHub MCP
      log("[10/11] Creating Pull Request")
      pr_body = build_pr_body(inputs, plan, generated_files)

      pr_result = github_client.create_pull_request(repository, {
        title: inputs['ticket_title'],
        body: pr_body,
        head: branch_name,
        base: 'main'
      })

      unless pr_result[:success]
        raise "Failed to create PR: #{pr_result[:error]}"
      end

      log("PR created: #{pr_result[:pr_url]}")

      # Complete agent execution with outputs
      agent_execution.complete!(
        branch_name: branch_name,
        pr_url: pr_result[:pr_url],
        pr_id: pr_result[:pr_id],
        pr_number: pr_result[:pr_number],
        files_changed: generated_files.length,
        commit_sha: push_result[:commit_sha]
      )

      # Update pipeline execution
      pipeline_execution.update!(
        branch_name: branch_name,
        pr_url: pr_result[:pr_url],
        pr_id: pr_result[:pr_id]
      )

      log("[11/11] Workflow complete! PR: #{pr_result[:pr_url]}")

    ensure
      # STEP 11: Cleanup workspace
      begin
        workspace_manager.cleanup_workspace! if workspace_manager && workspace_manager.respond_to?(:workspace_path) && workspace_manager.workspace_path.present?
      rescue => e
        log("Warning: workspace cleanup failed: #{e.message}")
      end
    end

    private

    # Clone repository to workspace using git command
    def clone_repository_to_workspace(repository, token)
      repo_url = "https://#{token}@github.com/#{repository}.git"
      repo_path = File.join(workspace_manager.workspace_path, 'repo')

      # Use git clone
      clone_cmd = "git clone --depth 1 #{repo_url} #{repo_path} 2>&1"
      result = `#{clone_cmd}`

      unless $?.success?
        raise "Failed to clone repository: #{result}"
      end

      log("Repository cloned to: #{repo_path}")
      repo_path
    end

    # Generate code using Claude with structured output
    def generate_code_with_claude(plan, inputs)
      system_prompt = build_coder_system_prompt
      user_message = build_coder_user_message(plan, inputs)

      result = call_claude(
        system_prompt,
        user_message,
        model: 'qwen3-next-80b',
        max_tokens: 8000,
        temperature: 0.3
      )

      return { success: false, error: result[:error] } unless result[:success]

      # Parse generated code into file structures
      files = parse_code_blocks(result[:content])

      {
        success: true,
        files: files,
        raw_output: result[:content]
      }
    rescue => e
      { success: false, error: e.message }
    end

    def build_coder_system_prompt
      <<~PROMPT
        You are an expert software developer implementing features for a Ruby on Rails application.

        You will generate production-ready code based on implementation plans.

        IMPORTANT: Format your response as follows:

        For each file to create or modify, use this exact format:

        FILE: path/to/file.rb
        ```ruby
        # Complete file contents here
        ```

        FILE: path/to/test_file_spec.rb
        ```ruby
        # Complete test file contents here
        ```

        Generate complete, working files. Do not use placeholders or TODOs.
        Include proper:
        - Error handling
        - Input validation
        - Tests (RSpec for Ruby)
        - Comments for complex logic
        - Following Rails best practices

        Always create corresponding test files for any code you write.
      PROMPT
    end

    def build_coder_user_message(plan, inputs)
      <<~MESSAGE
        Implement the following feature:

        Ticket: #{inputs['ticket_id']} - #{inputs['ticket_title']}

        Implementation Plan:
        #{plan}

        Repository: #{inputs['repository']}

        Generate all necessary files including tests.
        Use the FILE: format specified in the system prompt.
      MESSAGE
    end

    # Parse code blocks from Claude's response
    def parse_code_blocks(response)
      files = []

      # Match FILE: path/to/file.ext followed by code block
      response.scan(/FILE:\s*([^\n]+)\n```[\w]*\n(.*?)\n```/m) do |path, content|
        files << {
          path: path.strip,
          content: content.strip
        }
      end

      # Fallback: if no FILE: markers, try to extract code blocks with filenames
      if files.empty?
        response.scan(/```(\w+)\s+#\s*([^\n]+)\n(.*?)\n```/m) do |lang, path, content|
          files << {
            path: path.strip,
            content: content.strip
          }
        end
      end

      files
    end

    def build_commit_message(title, ticket_id)
      <<~MSG.strip
        Implement #{title}

        Ticket: #{ticket_id}

        Generated by AI Pipeline
        🤖 Automated code generation via Claude Sonnet 4.5
      MSG
    end

    def build_pr_body(inputs, plan, files)
      <<~BODY
        ## 🎫 Ticket
        **#{inputs['ticket_id']}**: #{inputs['ticket_title']}

        ## 📋 Implementation Plan
        #{plan.lines.first(20).join}
        #{plan.lines.count > 20 ? "\n... (see full plan in artifacts)" : ""}

        ## 📁 Files Changed (#{files.length})
        #{files.map { |f| "- `#{f[:path]}`" }.join("\n")}

        ## 🤖 Generated by AI Pipeline
        - Agent: CoderAgent
        - Model: Claude Sonnet 4.5
        - Timestamp: #{Time.current.iso8601}

        ## ✅ Next Steps
        1. ReviewerAgent will analyze code quality
        2. Automated tests will run
        3. Human approval for production deployment
      BODY
    end
  end
end
