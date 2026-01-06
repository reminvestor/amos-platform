# frozen_string_literal: true

namespace :platform_evolution do
  desc "Show Platform Evolution Engine status"
  task :status => :environment do
    puts "\n" + "="*70
    puts "🧬 PLATFORM EVOLUTION ENGINE STATUS"
    puts "="*70

    puts "\n📊 TICKETS:"
    puts "  Total:           #{SupportTicket.count}"
    puts "  Open:            #{SupportTicket.open_tickets.count}"
    puts "  Critical:        #{SupportTicket.critical.open_tickets.count}"
    puts "  From Logs:       #{SupportTicket.from_logs.count}"
    puts "  From Users:      #{SupportTicket.from_users.count}"
    puts "  Resolved:        #{SupportTicket.resolved.count}"

    puts "\n🔍 DEBUG SESSIONS:"
    puts "  Total:           #{DebugSession.count}"
    puts "  Active:          #{DebugSession.active.count}"
    puts "  Completed:       #{DebugSession.completed.count}"

    puts "\n🔧 CODE FIXES:"
    puts "  Total:           #{CodeFix.count}"
    puts "  Pending:         #{CodeFix.pending.count}"
    puts "  Validated:       #{CodeFix.validated.count}"
    puts "  Applied:         #{CodeFix.applied.count}"

    puts "\n📝 PULL REQUESTS:"
    puts "  Total:           #{PullRequestSubmission.count}"
    puts "  Open:            #{PullRequestSubmission.open_prs.count}"
    puts "  Merged:          #{PullRequestSubmission.merged.count}"

    puts "\n⚠️ ERROR LOG ENTRIES:"
    puts "  Total (24h):     #{ErrorLogEntry.today.count}"
    puts "  Unprocessed:     #{ErrorLogEntry.unprocessed.count}"

    puts "\n" + "="*70 + "\n"
  end

  desc "Run log monitor to scan for errors"
  task :scan_logs, [:entity_id] => :environment do |t, args|
    entity = args.entity_id ? Entity.find(args.entity_id) : Entity.first
    raise "No entity found" unless entity

    puts "🔍 Scanning logs for #{entity.name}..."
    
    service = PlatformEvolution::LogMonitorService.new(entity)
    result = service.monitor_once

    puts "✅ Scan complete:"
    puts "  Processed:       #{result[:processed]}"
    puts "  Unique errors:   #{result[:unique_errors]}"
    puts "  Tickets created: #{result[:tickets_created]}"
  end

  desc "Start debug session for a ticket"
  task :debug, [:ticket_number] => :environment do |t, args|
    raise "Usage: rake platform_evolution:debug[AMOS-00001]" unless args.ticket_number

    ticket = SupportTicket.find_by!(ticket_number: args.ticket_number.upcase)

    puts "🔍 Starting debug session for #{ticket.ticket_number}..."
    
    service = PlatformEvolution::DebugAgentService.new(ticket)
    session = service.start_debugging!

    puts "✅ Debug session started:"
    puts "  Session ID:      #{session.session_id}"
    puts "  Status:          #{session.status}"
    puts "  Confidence:      #{(session.confidence_score.to_f * 100).round}%"
    puts "  Root Cause:      #{session.root_cause_analysis&.truncate(100) || 'Analyzing...'}"
  end

  desc "Generate code fix from debug session"
  task :generate_fix, [:session_id] => :environment do |t, args|
    raise "Usage: rake platform_evolution:generate_fix[dbg_xxx]" unless args.session_id

    session = DebugSession.find_by!(session_id: args.session_id)

    puts "🔧 Generating fix for session #{session.session_id}..."
    
    service = PlatformEvolution::CodeFixAgentService.new(session)
    fix = service.generate_fix!

    if fix
      puts "✅ Fix generated:"
      puts "  Fix ID:          #{fix.fix_id}"
      puts "  Status:          #{fix.status}"
      puts "  Tests Passed:    #{fix.tests_passed ? 'Yes' : 'No'}"
      puts "  Files Changed:   #{fix.files_changed_count}"
    else
      puts "❌ Could not generate fix"
    end
  end

  desc "Create PR for a validated code fix"
  task :create_pr, [:fix_id] => :environment do |t, args|
    raise "Usage: rake platform_evolution:create_pr[fix_xxx]" unless args.fix_id

    fix = CodeFix.find_by!(fix_id: args.fix_id)
    raise "Fix not validated" unless fix.tests_passed

    puts "📝 Creating PR for fix #{fix.fix_id}..."
    
    service = PlatformEvolution::GitHubPRService.new(fix)
    pr = service.create_pull_request!

    if pr
      puts "✅ PR created:"
      puts "  PR Number:       ##{pr.pr_number}"
      puts "  URL:             #{pr.pr_url}"
      puts "  Status:          #{pr.status}"
    else
      puts "❌ Could not create PR"
    end
  end

  desc "Simulate the full evolution pipeline"
  task :demo => :environment do
    entity = Entity.first
    raise "No entity found" unless entity

    puts "\n🧬 PLATFORM EVOLUTION ENGINE DEMO"
    puts "="*50

    # Step 1: Create a sample error
    puts "\n1️⃣ Simulating error detection..."
    error = ErrorLogEntry.capture_error!(
      error_class: 'NameError',
      error_message: "undefined local variable or method 'foo' for #<SomeService>",
      stack_trace: "app/services/some_service.rb:42:in `process'\napp/controllers/some_controller.rb:10:in `create'",
      entity: entity,
      context: { demo: true }
    )
    puts "   Error captured: #{error.error_signature}"

    # Step 2: Create ticket from error
    puts "\n2️⃣ Creating support ticket..."
    ticket = SupportTicket.create_from_error!(
      entity: entity,
      error_class: error.error_class,
      error_message: error.error_message,
      stack_trace: error.stack_trace,
      context: error.context
    )
    puts "   Ticket created: #{ticket.ticket_number}"

    # Step 3: Create debug session
    puts "\n3️⃣ Creating debug session..."
    session = ticket.create_debug_session!
    session.add_agent_message("Analyzing error: #{ticket.error_class}")
    session.set_root_cause!(
      analysis: "The variable 'foo' is not defined before being used. This appears to be a typo or missing initialization.",
      confidence: 0.85
    )
    session.add_proposed_fix(
      description: "Initialize the 'foo' variable before use",
      files: ['app/services/some_service.rb'],
      risk_level: 'low',
      estimated_impact: 'Fixes the NameError'
    )
    session.select_fix!(index: 0, rationale: "Simple initialization fix")
    puts "   Debug session: #{session.session_id}"
    puts "   Confidence: #{(session.confidence_score.to_f * 100).round}%"

    # Step 4: Create code fix
    puts "\n4️⃣ Creating code fix..."
    fix = session.create_code_fix!(
      files_modified: [
        {
          path: 'app/services/some_service.rb',
          original_content: "def process\n  bar = foo + 1\nend",
          modified_content: "def process\n  foo = 0\n  bar = foo + 1\nend"
        }
      ],
      fix_description: "Initialize foo variable",
      risk_level: 'low'
    )
    fix.record_test_results!(tests_run: 10, tests_passed: 10, tests_failed: 0, output: "All tests passed")
    fix.record_lint_results!(passed: true, output: "No offenses detected")
    puts "   Fix created: #{fix.fix_id}"
    puts "   Tests: ✅ Passed"

    # Step 5: Create PR
    puts "\n5️⃣ Creating pull request..."
    pr = fix.create_pull_request!(
      pr_number: '1234',
      pr_url: 'https://github.com/example/repo/pull/1234',
      pr_title: "Fix: [#{ticket.ticket_number}] Initialize foo variable",
      pr_body: "Fixes NameError by initializing foo variable"
    )
    puts "   PR created: ##{pr.pr_number}"
    puts "   URL: #{pr.pr_url}"

    puts "\n✅ DEMO COMPLETE"
    puts "="*50
    puts "\nThe evolution pipeline is ready!"
    puts "When real errors occur, they will be:"
    puts "  1. Detected by LogMonitor"
    puts "  2. Converted to tickets"
    puts "  3. Debugged by AI"
    puts "  4. Fixed automatically"
    puts "  5. Submitted as PRs for human approval"
    puts "\nView in admin: /admin/platform_evolution"
    puts "="*50
  end

  desc "Clean up demo data"
  task :clean_demo => :environment do
    puts "🧹 Cleaning up demo data..."
    
    PullRequestSubmission.where("pr_title LIKE '%demo%' OR pr_title LIKE '%DEMO%'").destroy_all
    CodeFix.joins(:support_ticket).where("support_tickets.error_context->>'demo' = 'true'").destroy_all
    DebugSession.joins(:support_ticket).where("support_tickets.error_context->>'demo' = 'true'").destroy_all
    SupportTicket.where("error_context->>'demo' = 'true'").destroy_all
    ErrorLogEntry.where("context->>'demo' = 'true'").destroy_all
    
    puts "✅ Demo data cleaned"
  end
end


