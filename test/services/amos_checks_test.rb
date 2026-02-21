# frozen_string_literal: true

require "test_helper"

class AmosChecksTest < ActiveSupport::TestCase
  fixtures :entities, :users

  setup do
    @entity = entities(:one)
    @user = users(:one)
  end

  # ═══════════════════════════════════════════════════════════════
  # FRAMEWORK: Registry
  # ═══════════════════════════════════════════════════════════════

  test "registry lists all registered checks" do
    checks = AmosChecks::Registry.registered_checks
    assert checks.is_a?(Array)
    assert checks.any?, "Should have at least one registered check"

    names = checks.map { |c| c[:name] }
    assert_includes names, :stuck_modules
    assert_includes names, :stale_plans
    assert_includes names, :failed_builds
  end

  test "registry runs all health checks without error" do
    findings = AmosChecks::Registry.run_health_checks
    assert findings.is_a?(Array)
  end

  test "registry filters by category" do
    health = AmosChecks::Registry.run_all(categories: [:platform_health])
    assert health.is_a?(Array)

    improvement = AmosChecks::Registry.run_all(categories: [:platform_improvement])
    assert improvement.is_a?(Array)
  end

  # ═══════════════════════════════════════════════════════════════
  # FRAMEWORK: Finding
  # ═══════════════════════════════════════════════════════════════

  test "finding calculates signal_strength from severity" do
    finding = AmosChecks::Finding.new(
      check_name: :test, category: :platform_health, severity: :critical,
      scope: :platform, summary: "Test"
    )
    assert_equal 0.95, finding.signal_strength

    finding_high = AmosChecks::Finding.new(
      check_name: :test, category: :platform_health, severity: :high,
      scope: :platform, summary: "Test"
    )
    assert_equal 0.8, finding_high.signal_strength
  end

  test "finding knows its signal_type from category" do
    health = AmosChecks::Finding.new(
      check_name: :test, category: :platform_health, severity: :high,
      scope: :platform, summary: "Test"
    )
    assert_equal "platform_health_issue", health.signal_type

    improvement = AmosChecks::Finding.new(
      check_name: :test, category: :platform_improvement, severity: :medium,
      scope: :platform, summary: "Test"
    )
    assert_equal "platform_improvement", improvement.signal_type
  end

  test "finding is actionable when high+ severity and create_bounty action" do
    actionable = AmosChecks::Finding.new(
      check_name: :test, category: :platform_health, severity: :high,
      scope: :platform, summary: "Test", suggested_action: :create_bounty
    )
    assert actionable.actionable?

    not_actionable = AmosChecks::Finding.new(
      check_name: :test, category: :platform_health, severity: :medium,
      scope: :platform, summary: "Test", suggested_action: :create_bounty
    )
    refute not_actionable.actionable?

    investigate = AmosChecks::Finding.new(
      check_name: :test, category: :platform_health, severity: :high,
      scope: :platform, summary: "Test", suggested_action: :investigate
    )
    refute investigate.actionable?
  end

  # ═══════════════════════════════════════════════════════════════
  # CHECK: StuckModulesCheck
  # ═══════════════════════════════════════════════════════════════

  test "stuck_modules_check detects modules stuck in generating" do
    slug = "stuck_test_#{SecureRandom.hex(4)}"

    mod = AppModule.create!(
      entity: @entity,
      name: "Stuck Test Module",
      slug: slug,
      status: "generating",
      created_at: 2.hours.ago,
      updated_at: 2.hours.ago
    )

    ModuleCode.create!(
      app_module: mod,
      entity: @entity,
      name: "StuckTest",
      code_type: "model",
      content: "class StuckTest; end",
      version: 1
    )

    ActiveRecord::Base.connection.create_table(slug.pluralize, if_not_exists: true) do |t|
      t.references :entity, null: false
      t.timestamps
    end

    begin
      check = AmosChecks::Platform::StuckModulesCheck.new
      findings = check.run

      stuck_finding = findings.find { |f| f.details[:module_ids]&.include?(mod.id) }
      assert stuck_finding, "Should detect the stuck module"
      assert stuck_finding.severity.in?([:critical, :high])
      assert_equal :auto_recover, stuck_finding.suggested_action
      assert stuck_finding.details[:recoverable]
      assert stuck_finding.bounty_params.present?
    ensure
      ActiveRecord::Base.connection.drop_table(slug.pluralize, if_exists: true)
      mod.module_codes.destroy_all
      mod.destroy!
    end
  end

  test "stuck_modules_check ignores recently created modules" do
    mod = AppModule.create!(
      entity: @entity,
      name: "Fresh Module",
      slug: "fresh_mod_#{SecureRandom.hex(4)}",
      status: "generating"
    )

    begin
      check = AmosChecks::Platform::StuckModulesCheck.new
      findings = check.run

      fresh_finding = findings.find { |f| f.details[:module_ids]&.include?(mod.id) }
      assert_nil fresh_finding, "Should not flag modules created less than 1 hour ago"
    ensure
      mod.destroy!
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CHECK: StalePlansCheck
  # ═══════════════════════════════════════════════════════════════

  test "stale_plans_check detects plans stuck in building" do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Stale Plan Test",
      description: "Testing stale detection",
      status: "building",
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago
    )

    begin
      check = AmosChecks::Platform::StalePlansCheck.new
      findings = check.run

      stale_finding = findings.find { |f| f.details[:plan_id] == plan.id }
      assert stale_finding, "Should detect the stale plan"
      assert stale_finding.severity.in?([:high, :medium])
      assert stale_finding.bounty_params.present?
    ensure
      ApplicationPlan.where(id: plan.id).delete_all
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # CHECK: FailedBuildsCheck
  # ═══════════════════════════════════════════════════════════════

  test "failed_builds_check detects failure spikes" do
    plans = 6.times.map do |i|
      ApplicationPlan.create!(
        entity: @entity,
        created_by: @user,
        name: "Failed Plan #{i}",
        description: "Testing failure spike",
        status: "failed",
        error_message: "Test failure: something went wrong",
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )
    end

    begin
      check = AmosChecks::Platform::FailedBuildsCheck.new
      findings = check.run

      spike_finding = findings.find { |f| f.check_name == :failed_builds && f.details[:failure_count].to_i >= 5 }
      assert spike_finding, "Should detect failure spike with #{plans.size} failures"
      assert spike_finding.details[:error_patterns].present?
    ensure
      ApplicationPlan.where(id: plans.map(&:id)).delete_all
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # SIGNAL INTEGRATION
  # ═══════════════════════════════════════════════════════════════

  test "AmosSignal accepts platform_health_issue signal type" do
    signal = AmosSignal.record!(
      entity: @entity,
      signal_type: "platform_health_issue",
      source: "platform_health_scanner",
      strength: 0.8,
      summary: "Test platform health signal",
      data: { check_name: "stuck_modules", severity: "high" }
    )

    assert signal.persisted?
    assert_equal "platform_health_issue", signal.signal_type
    assert_equal "platform_health_scanner", signal.source
  ensure
    signal&.destroy
  end

  # ═══════════════════════════════════════════════════════════════
  # SIGNAL-DRIVEN BOUNTY CREATION
  # ═══════════════════════════════════════════════════════════════

  test "create_bounty_from_signal creates bounty from signal with bounty_params" do
    loop_service = AmosAutonomousLoop.new(@entity)
    loop_service.instance_variable_set(:@session, AmosThinkingSession.create!(
      entity: @entity, session_type: "autonomous", status: "running"
    ))

    unique_title = "Recover 5 stuck app modules (test-#{SecureRandom.hex(8)})"
    signal = {
      type: :platform_health,
      label: "5 stuck modules",
      strength: 0.8,
      data: {
        bounty_params: {
          title: unique_title,
          description: "5 modules are stuck in generating status.",
          bounty_type: "infrastructure",
          points: 150
        }
      }
    }

    bounty = loop_service.send(:create_bounty_from_signal, signal)
    assert bounty, "Should create a bounty from signal with bounty_params"
    assert bounty.persisted?
    assert_equal "infrastructure", bounty.bounty_type
    assert_equal 150, bounty.points
    assert_includes bounty.title, "Recover 5 stuck"
  ensure
    Bounty.where(title: unique_title).delete_all
  end

  test "create_bounty_from_signal skips signals without bounty_params" do
    loop_service = AmosAutonomousLoop.new(@entity)
    loop_service.instance_variable_set(:@session, AmosThinkingSession.create!(
      entity: @entity, session_type: "autonomous", status: "running"
    ))

    signal = {
      type: :platform_health,
      label: "Something happened",
      strength: 0.8,
      data: { check_name: "test" }
    }

    bounty = loop_service.send(:create_bounty_from_signal, signal)
    assert_nil bounty, "Should not create bounty without bounty_params"
  end

  test "create_bounty_from_signal skips weak signals" do
    loop_service = AmosAutonomousLoop.new(@entity)
    loop_service.instance_variable_set(:@session, AmosThinkingSession.create!(
      entity: @entity, session_type: "autonomous", status: "running"
    ))

    signal = {
      type: :platform_health,
      label: "Minor issue",
      strength: 0.3,
      data: {
        bounty_params: {
          title: "Should not be created",
          description: "Too weak",
          bounty_type: "infrastructure",
          points: 50
        }
      }
    }

    bounty = loop_service.send(:create_bounty_from_signal, signal)
    assert_nil bounty, "Should not create bounty for weak signals"
  end

  test "create_bounty_from_signal deduplicates by title" do
    loop_service = AmosAutonomousLoop.new(@entity)
    loop_service.instance_variable_set(:@session, AmosThinkingSession.create!(
      entity: @entity, session_type: "autonomous", status: "running"
    ))

    unique_title = "Dedup test bounty #{SecureRandom.hex(8)}"

    Bounty.create!(
      entity: @entity,
      title: unique_title,
      description: "Already exists",
      bounty_type: "infrastructure",
      points: 100,
      source: "amos_thinking",
      ai_scoring_rationale: "test"
    )

    signal = {
      type: :platform_health,
      label: "Duplicate",
      strength: 0.8,
      data: { bounty_params: { title: unique_title, description: "Dup", bounty_type: "infrastructure", points: 100 } }
    }

    bounty = loop_service.send(:create_bounty_from_signal, signal)
    assert_nil bounty, "Should not create duplicate bounty"
  ensure
    Bounty.where(title: unique_title).delete_all
  end

  # ═══════════════════════════════════════════════════════════════
  # PERCEPTION: perceive_platform_health
  # ═══════════════════════════════════════════════════════════════

  test "perceive_platform_health converts findings to signals" do
    loop_service = AmosAutonomousLoop.new(@entity)
    signals = loop_service.send(:perceive_platform_health)

    assert signals.is_a?(Array)
    signals.each do |s|
      assert_equal :platform_health, s[:type]
      assert s[:strength].is_a?(Numeric)
      assert s[:label].present?
      assert s[:suggested_action].present?
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # JOB: PlatformHealthScanJob
  # ═══════════════════════════════════════════════════════════════

  test "PlatformHealthScanJob runs without error" do
    assert_nothing_raised do
      PlatformHealthScanJob.perform_now
    end
  end

  test "PlatformHealthScanJob emits signals for findings" do
    slug = "scan_job_test_#{SecureRandom.hex(4)}"
    mod = AppModule.create!(
      entity: @entity,
      name: "Scan Job Stuck Module",
      slug: slug,
      status: "generating",
      created_at: 2.hours.ago,
      updated_at: 2.hours.ago
    )

    ModuleCode.create!(
      app_module: mod,
      entity: @entity,
      name: "ScanJobTest",
      code_type: "model",
      content: "class ScanJobTest; end",
      version: 1
    )

    ActiveRecord::Base.connection.create_table(slug.pluralize, if_not_exists: true) do |t|
      t.references :entity, null: false
      t.timestamps
    end

    begin
      initial_count = AmosSignal.where(signal_type: "platform_health_issue").count
      PlatformHealthScanJob.perform_now
      new_count = AmosSignal.where(signal_type: "platform_health_issue").count

      assert new_count > initial_count, "Should have emitted at least one platform_health_issue signal"
    ensure
      ActiveRecord::Base.connection.drop_table(slug.pluralize, if_exists: true)
      mod.module_codes.destroy_all
      mod.destroy!
      AmosSignal.where(signal_type: "platform_health_issue").delete_all
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # REACTIVE: handle_platform_health_signals
  # ═══════════════════════════════════════════════════════════════

  test "reactive session auto-recovers stuck modules" do
    slug = "reactive_test_#{SecureRandom.hex(4)}"
    mod = AppModule.create!(
      entity: @entity,
      name: "Reactive Test Module",
      slug: slug,
      status: "generating",
      created_at: 2.hours.ago,
      updated_at: 2.hours.ago
    )

    ModuleCode.create!(
      app_module: mod,
      entity: @entity,
      name: "ReactiveTest",
      code_type: "model",
      content: "class ReactiveTest; end",
      version: 1
    )

    ActiveRecord::Base.connection.create_table(slug.pluralize, if_not_exists: true) do |t|
      t.references :entity, null: false
      t.timestamps
    end

    begin
      job = AmosReactiveSessionJob.new

      check_data = {
        "check_name" => "stuck_modules",
        "severity" => "high",
        "suggested_action" => "auto_recover",
        "details" => {
          "module_ids" => [mod.id],
          "recoverable" => true
        }
      }

      result = job.send(:attempt_auto_recovery, @entity, check_data)
      assert result, "Should successfully auto-recover the module"

      mod.reload
      assert_equal "active", mod.status, "Module should be activated after auto-recovery"
    ensure
      ActiveRecord::Base.connection.drop_table(slug.pluralize, if_exists: true)
      mod.module_codes.destroy_all
      mod.destroy!
    end
  end

  test "reactive session auto-recovers stale plans with active modules" do
    plan = ApplicationPlan.create!(
      entity: @entity,
      created_by: @user,
      name: "Reactive Stale Plan",
      description: "Test",
      status: "building",
      build_results: { "completed_phases" => ["modules"] },
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago
    )

    # Create an active module in the same entity so recovery can complete the plan
    active_mod = AppModule.create!(
      entity: @entity,
      name: "Active Module For Plan",
      slug: "active_for_plan_#{SecureRandom.hex(4)}",
      status: "active"
    )

    begin
      job = AmosReactiveSessionJob.new

      check_data = {
        "check_name" => "stale_plans",
        "severity" => "high",
        "suggested_action" => "auto_recover",
        "details" => {
          "plan_id" => plan.id,
          "resolvable" => true,
          "recoverable" => true
        }
      }

      result = job.send(:attempt_auto_recovery, @entity, check_data)
      assert result, "Should successfully auto-recover the stale plan"

      plan.reload
      assert_equal "completed", plan.status, "Plan should be marked completed after auto-recovery"
    ensure
      ApplicationPlan.where(id: plan.id).delete_all
      active_mod.destroy!
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # EXTENSIBILITY: Adding new checks
  # ═══════════════════════════════════════════════════════════════

  test "finding to_signal_data produces valid signal data hash" do
    finding = AmosChecks::Finding.new(
      check_name: :test_check,
      category: :platform_health,
      severity: :high,
      scope: :entity,
      entity_id: @entity.id,
      summary: "Test finding",
      details: { count: 5, items: [1, 2, 3] },
      suggested_action: :create_bounty,
      bounty_params: { title: "Fix it", points: 100 }
    )

    data = finding.to_signal_data
    assert_equal "test_check", data["check_name"]
    assert_equal "high", data["severity"]
    assert_equal "entity", data["scope"]
    assert_equal "Test finding", data["summary"]
    assert_equal "create_bounty", data["suggested_action"]
  end

  test "entity_insight checks require entity" do
    entity_findings = AmosChecks::Registry.run_all(categories: [:entity_insight])
    assert_equal [], entity_findings, "Entity insight checks should return nothing without an entity"
  end
end
