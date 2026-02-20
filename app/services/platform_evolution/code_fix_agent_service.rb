# frozen_string_literal: true

module PlatformEvolution
  # CodeFixAgentService - Generates and validates code fixes
  #
  # This service:
  # 1. Takes a proposed fix from DebugAgent
  # 2. Generates the actual code changes
  # 3. Creates a git branch
  # 4. Runs tests to validate
  # 5. Prepares for PR submission
  #
  class CodeFixAgentService


    attr_reader :session, :ticket, :code_fix

    SYSTEM_PROMPT = <<~PROMPT
      You are a senior Rails developer implementing a bug fix.

      Your task is to generate the exact code changes needed to fix the issue.
      
      Rules:
      1. Only modify the minimum code necessary
      2. Follow existing code style and conventions
      3. Add comments if the fix isn't obvious
      4. Consider edge cases
      5. Don't break existing functionality

      Respond with JSON:
      {
        "changes": [
          {
            "file": "path/to/file.rb",
            "original": "exact original code to replace",
            "replacement": "the new code",
            "line_hint": 42
          }
        ],
        "test_changes": [
          {
            "file": "test/path/to/test.rb",
            "new_test": "def test_fix_works\\n  # test code\\nend"
          }
        ],
        "commit_message": "Fix: Brief description",
        "notes": "Any additional context"
      }
    PROMPT

    def initialize(debug_session)
      @session = debug_session
      @ticket = session.support_ticket
      @code_fix = nil
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # MAIN FIX GENERATION FLOW
    # ═══════════════════════════════════════════════════════════════════════════

    def generate_fix!
      raise "No fix selected" unless session.selected_fix

      Rails.logger.info "[CodeFixAgent] Generating fix for #{ticket.ticket_number}"

      # Step 1: Generate code changes with AI
      changes = generate_code_changes

      return nil unless changes && changes[:changes].present?

      # Step 2: Create code fix record
      @code_fix = create_code_fix_record(changes)

      # Step 3: Create git branch and apply changes
      apply_changes_to_branch(@code_fix, changes)

      # Step 4: Run tests
      run_tests(@code_fix)

      @code_fix
    end

    def generate_code_changes
      context = build_generation_context
      prompt = build_generation_prompt(context)

      response = call_ai(
        system_prompt: SYSTEM_PROMPT,
        user_prompt: prompt
      )

      parse_ai_response(response)
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CONTEXT BUILDING
    # ═══════════════════════════════════════════════════════════════════════════

    def build_generation_context
      fix = session.selected_fix

      context = {
        ticket: ticket.to_context,
        root_cause: session.root_cause_analysis,
        proposed_fix: fix,
        files_to_modify: fix['files'] || fix[:files] || []
      }

      # Read the actual file contents
      context[:file_contents] = {}
      context[:files_to_modify].each do |file_path|
        full_path = Rails.root.join(file_path)
        if File.exist?(full_path)
          context[:file_contents][file_path] = File.read(full_path)
        end
      end

      context
    end

    def build_generation_prompt(context)
      files_section = context[:file_contents].map do |path, content|
        <<~FILE
          ### File: #{path}
          ```ruby
          #{content}
          ```
        FILE
      end.join("\n")

      <<~PROMPT
        ## Issue to Fix

        **Ticket:** #{context[:ticket][:ticket_number]}
        **Error:** #{context[:ticket][:error_class]}: #{context[:ticket][:error_message]}

        **Root Cause:** #{context[:root_cause]}

        **Proposed Fix:** #{context[:proposed_fix]['description'] || context[:proposed_fix][:description]}

        ## Files to Modify

        #{files_section}

        Please generate the exact code changes needed to fix this issue.
      PROMPT
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # CODE FIX CREATION
    # ═══════════════════════════════════════════════════════════════════════════

    def create_code_fix_record(changes)
      files_modified = changes[:changes].map do |change|
        {
          path: change['file'] || change[:file],
          original_content: change['original'] || change[:original],
          modified_content: change['replacement'] || change[:replacement],
          line_hint: change['line_hint'] || change[:line_hint]
        }
      end

      session.create_code_fix!(
        files_modified: files_modified,
        fix_description: changes[:commit_message] || changes['commit_message'],
        risk_level: determine_risk_level(files_modified)
      )
    end

    def determine_risk_level(files)
      paths = files.map { |f| f[:path] || f['path'] }

      return 'critical' if paths.any? { |p| p.include?('migration') || p.include?('schema') }
      return 'high' if paths.any? { |p| p.include?('/models/') || p.include?('billing') }
      return 'low' if paths.all? { |p| p.include?('_test.rb') || p.include?('/spec/') }

      'medium'
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # GIT OPERATIONS
    # ═══════════════════════════════════════════════════════════════════════════

    def apply_changes_to_branch(code_fix, changes)
      branch_name = code_fix.create_branch!
      
      Rails.logger.info "[CodeFixAgent] Creating branch: #{branch_name}"

      # In a real implementation, we would:
      # 1. git checkout -b branch_name
      # 2. Apply each file change
      # 3. git add + commit
      # 4. git push

      # For now, we'll simulate this and store the changes
      git_service = GitService.new

      begin
        # Create branch
        git_service.create_branch(branch_name)

        # Apply changes
        changes[:changes].each do |change|
          file_path = change['file'] || change[:file]
          original = change['original'] || change[:original]
          replacement = change['replacement'] || change[:replacement]

          git_service.apply_change(file_path, original, replacement)
        end

        # Commit
        commit_message = changes[:commit_message] || changes['commit_message'] || "Fix: #{ticket.ticket_number}"
        commit_sha = git_service.commit(commit_message)

        code_fix.record_commit!(commit_sha: commit_sha)

        Rails.logger.info "[CodeFixAgent] Committed changes: #{commit_sha}"
      rescue => e
        Rails.logger.error "[CodeFixAgent] Git operation failed: #{e.message}"
        # Record the failure but don't block - changes are still stored in the record
      end
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # TESTING
    # ═══════════════════════════════════════════════════════════════════════════

    def run_tests(code_fix)
      code_fix.start_testing!

      Rails.logger.info "[CodeFixAgent] Running tests..."

      # Run relevant tests
      test_output = run_relevant_tests(code_fix.file_paths)

      # Parse results
      tests_run = test_output.scan(/(\d+) runs/).flatten.first&.to_i || 0
      tests_passed = tests_run - (test_output.scan(/(\d+) failures/).flatten.first&.to_i || 0)
      tests_failed = test_output.scan(/(\d+) failures/).flatten.first&.to_i || 0

      code_fix.record_test_results!(
        tests_run: tests_run,
        tests_passed: tests_passed,
        tests_failed: tests_failed,
        output: test_output
      )

      # Also run linting
      lint_output = run_linting(code_fix.file_paths)
      lint_passed = !lint_output.include?('offense') && !lint_output.include?('error')

      code_fix.record_lint_results!(passed: lint_passed, output: lint_output)

      code_fix.tests_passed && lint_passed
    end

    def run_relevant_tests(file_paths)
      # Determine which tests to run based on changed files
      test_files = file_paths.map do |path|
        path.gsub('app/', 'test/').gsub('.rb', '_test.rb')
      end.select { |f| File.exist?(Rails.root.join(f)) }

      if test_files.any?
        `cd #{Rails.root} && bin/rails test #{test_files.join(' ')} 2>&1`
      else
        # Run full test suite if we can't identify specific tests
        `cd #{Rails.root} && bin/rails test 2>&1 | tail -20`
      end
    rescue => e
      "Test execution failed: #{e.message}"
    end

    def run_linting(file_paths)
      files = file_paths.join(' ')
      `cd #{Rails.root} && bundle exec rubocop #{files} 2>&1`
    rescue => e
      "Linting failed: #{e.message}"
    end

    # ═══════════════════════════════════════════════════════════════════════════
    # AI HELPERS
    # ═══════════════════════════════════════════════════════════════════════════

    def call_ai(system_prompt:, user_prompt:)
      service = BedrockLlmService.new(model: 'qwen3-next-80b')  # Cost-efficient with strong code understanding

      response = service.chat(
        messages: [{ role: 'user', content: user_prompt }],
        system_prompt: system_prompt,
        max_tokens: 4000
      )

      response[:content]
    rescue => e
      Rails.logger.error "[CodeFixAgent] AI call failed: #{e.message}"
      nil
    end

    def parse_ai_response(response)
      return nil if response.blank?

      json_match = response.match(/\{[\s\S]*\}/)
      return nil unless json_match

      JSON.parse(json_match[0]).with_indifferent_access
    rescue JSON::ParserError => e
      Rails.logger.warn "[CodeFixAgent] Could not parse AI response: #{e.message}"
      nil
    end
  end

  # Simple Git operations wrapper
  class GitService
    def initialize(repo_path: Rails.root)
      @repo_path = repo_path
    end

    def create_branch(name)
      run_git("checkout -b #{name}")
    end

    def apply_change(file_path, original, replacement)
      full_path = File.join(@repo_path, file_path)
      return unless File.exist?(full_path)

      content = File.read(full_path)
      new_content = content.gsub(original, replacement)
      File.write(full_path, new_content)
    end

    def commit(message)
      run_git("add -A")
      run_git("commit -m '#{message}'")
      run_git("rev-parse HEAD").strip
    end

    def push(branch)
      run_git("push origin #{branch}")
    end

    private

    def run_git(command)
      `cd #{@repo_path} && git #{command} 2>&1`
    end
  end
end

