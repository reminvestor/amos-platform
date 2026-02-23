# frozen_string_literal: true

require "test_helper"

class BenchmarkV2Test < ActiveSupport::TestCase
  setup do
    @entity = entities(:default)
    @user = users(:default)
  end

  # ═══════════════════════════════════════════════════════════════
  # Scenario Model
  # ═══════════════════════════════════════════════════════════════

  test "Scenario validates required fields" do
    scenario = Benchmarks::V2::Scenario.new(
      id: :test_scenario,
      level: :L2,
      category: :content_creation,
      name: "Test",
      description: "Test scenario",
      messages: ["Hello"],
      assertions: [{ type: :no_errors }],
      quality_rubric: "Score this."
    )

    assert_equal :test_scenario, scenario.id
    assert_equal :L2, scenario.level
    assert_equal 1, scenario.messages.size
  end

  test "Scenario rejects invalid level" do
    assert_raises ArgumentError do
      Benchmarks::V2::Scenario.new(
        id: :bad, level: :L99, category: :content_creation,
        name: "Bad", description: "Bad", messages: ["Hello"],
        assertions: [], quality_rubric: "Score this."
      )
    end
  end

  test "Scenario rejects invalid category" do
    assert_raises ArgumentError do
      Benchmarks::V2::Scenario.new(
        id: :bad, level: :L2, category: :nonexistent,
        name: "Bad", description: "Bad", messages: ["Hello"],
        assertions: [], quality_rubric: "Score this."
      )
    end
  end

  test "Scenario rejects empty messages" do
    assert_raises ArgumentError do
      Benchmarks::V2::Scenario.new(
        id: :bad, level: :L2, category: :content_creation,
        name: "Bad", description: "Bad", messages: [],
        assertions: [], quality_rubric: "Score this."
      )
    end
  end

  test "Scenario detects multi-turn" do
    single = Benchmarks::V2::Scenario.new(
      id: :single, level: :L2, category: :content_creation,
      name: "Single", description: "Single", messages: ["Hello"],
      assertions: [], quality_rubric: "Score."
    )

    multi = Benchmarks::V2::Scenario.new(
      id: :multi, level: :L2, category: :content_creation,
      name: "Multi", description: "Multi", messages: ["Hello", "World"],
      assertions: [], quality_rubric: "Score."
    )

    refute single.multi_turn?
    assert multi.multi_turn?
  end

  test "Scenario core? tag detection" do
    core = Benchmarks::V2::Scenario.new(
      id: :core, level: :L2, category: :content_creation,
      name: "Core", description: "Core", messages: ["Hello"],
      assertions: [], quality_rubric: "Score.", tags: [:core]
    )

    non_core = Benchmarks::V2::Scenario.new(
      id: :non_core, level: :L2, category: :content_creation,
      name: "Non-core", description: "Non-core", messages: ["Hello"],
      assertions: [], quality_rubric: "Score."
    )

    assert core.core?
    refute non_core.core?
  end

  test "Scenario to_h serialization" do
    scenario = Benchmarks::V2::Scenario.new(
      id: :test, level: :L3, category: :app_building,
      name: "Test", description: "Test", messages: ["Hello", "World"],
      assertions: [{ type: :no_errors }], quality_rubric: "Score.", tags: [:core]
    )

    h = scenario.to_h
    assert_equal :test, h[:id]
    assert_equal :L3, h[:level]
    assert_equal 2, h[:message_count]
    assert_equal 1, h[:assertion_count]
    assert_includes h[:tags], :core
  end

  # ═══════════════════════════════════════════════════════════════
  # ScenarioLibrary
  # ═══════════════════════════════════════════════════════════════

  test "ScenarioLibrary has registered scenarios" do
    assert Benchmarks::V2::ScenarioLibrary.count >= 8
    assert Benchmarks::V2::ScenarioLibrary.all.all? { |s| s.is_a?(Benchmarks::V2::Scenario) }
  end

  test "ScenarioLibrary get by ID" do
    scenario = Benchmarks::V2::ScenarioLibrary.get(:landing_page_multi_section)
    assert_not_nil scenario
    assert_equal :landing_page_multi_section, scenario.id
    assert_equal :L2, scenario.level
  end

  test "ScenarioLibrary core suite includes tagged scenarios" do
    core = Benchmarks::V2::ScenarioLibrary.core_suite
    assert core.any?
    assert core.all?(&:core?)
  end

  test "ScenarioLibrary by_level filters correctly" do
    l2_scenarios = Benchmarks::V2::ScenarioLibrary.by_level(:L2)
    assert l2_scenarios.any?
    assert l2_scenarios.all? { |s| s.level == :L2 }

    l4_scenarios = Benchmarks::V2::ScenarioLibrary.by_level(:L4)
    assert l4_scenarios.any?
    assert l4_scenarios.all? { |s| s.level == :L4 }
  end

  test "ScenarioLibrary by_category filters correctly" do
    content = Benchmarks::V2::ScenarioLibrary.by_category(:content_creation)
    assert content.any?
    assert content.all? { |s| s.category == :content_creation }
  end

  test "ScenarioLibrary returns IDs" do
    ids = Benchmarks::V2::ScenarioLibrary.ids
    assert ids.include?(:landing_page_multi_section)
    assert ids.include?(:app_build_multi_module)
    assert ids.include?(:ambiguous_request_handling)
  end

  # ═══════════════════════════════════════════════════════════════
  # Scorer - Structural Assertions
  # ═══════════════════════════════════════════════════════════════

  test "Scorer check_record_exists passes with matching records" do
    scenario = build_simple_scenario(
      assertions: [{ type: :record_exists, model: "Contact", min_count: 2 }]
    )

    execution = {
      transcript: [{ role: "assistant", content: "Created contacts" }],
      tool_calls: [],
      created_records: { "Contact" => [{ id: 1 }, { id: 2 }] },
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)
    assert result[:details].first[:passed]
  end

  test "Scorer check_record_exists fails with insufficient records" do
    scenario = build_simple_scenario(
      assertions: [{ type: :record_exists, model: "Contact", min_count: 3 }]
    )

    execution = {
      transcript: [{ role: "assistant", content: "Created" }],
      tool_calls: [],
      created_records: { "Contact" => [{ id: 1 }] },
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)
    refute result[:details].first[:passed]
  end

  test "Scorer check_record_exists filters by conditions" do
    scenario = build_simple_scenario(
      assertions: [{ type: :record_exists, model: "AppModule", conditions: { status: "active" }, min_count: 2 }]
    )

    execution = {
      transcript: [{ role: "assistant", content: "Built app" }],
      tool_calls: [],
      created_records: {
        "AppModule" => [
          { id: 1, status: "active" },
          { id: 2, status: "generating" },
          { id: 3, status: "active" }
        ]
      },
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)
    detail = result[:details].first
    assert detail[:passed], "Should pass: 2 active modules exist"
    assert_match(/active/, detail[:message])
  end

  test "Scorer check_record_exists conditions fail when insufficient matching" do
    scenario = build_simple_scenario(
      assertions: [{ type: :record_exists, model: "AppModule", conditions: { status: "active" }, min_count: 3 }]
    )

    execution = {
      transcript: [{ role: "assistant", content: "Built app" }],
      tool_calls: [],
      created_records: {
        "AppModule" => [
          { id: 1, status: "active" },
          { id: 2, status: "generating" },
          { id: 3, status: "generating" }
        ]
      },
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)
    refute result[:details].first[:passed], "Should fail: only 1 active module but need 3"
  end

  test "Scorer check_record_exists with empty conditions matches all records" do
    scenario = build_simple_scenario(
      assertions: [{ type: :record_exists, model: "Contact", conditions: {}, min_count: 2 }]
    )

    execution = {
      transcript: [{ role: "assistant", content: "Done" }],
      tool_calls: [],
      created_records: { "Contact" => [{ id: 1 }, { id: 2 }] },
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)
    assert result[:details].first[:passed]
  end

  test "Scorer check_tool_called passes" do
    scenario = build_simple_scenario(
      assertions: [{ type: :tool_called, tool_name: "platform_create", min_times: 2 }]
    )

    execution = {
      transcript: [{ role: "assistant", content: "Done" }],
      tool_calls: [
        { tool_name: "platform_create", success: true },
        { tool_name: "platform_create", success: true },
        { tool_name: "platform_query", success: true }
      ],
      created_records: {},
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)
    assert result[:details].first[:passed]
  end

  test "Scorer check_no_errors passes when clean" do
    scenario = build_simple_scenario(assertions: [{ type: :no_errors }])

    execution = {
      transcript: [{ role: "assistant", content: "Done" }],
      tool_calls: [{ tool_name: "platform_create", success: true }],
      created_records: {},
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)
    assert result[:details].first[:passed]
  end

  test "Scorer check_no_errors fails with tool errors" do
    scenario = build_simple_scenario(assertions: [{ type: :no_errors }])

    execution = {
      transcript: [{ role: "assistant", content: "Done" }],
      tool_calls: [{ tool_name: "platform_create", success: false, error: "failed" }],
      created_records: {},
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)
    refute result[:details].first[:passed]
  end

  test "Scorer check_conversation_completed" do
    scenario = build_simple_scenario(assertions: [{ type: :conversation_completed }])

    passed = {
      transcript: [{ role: "assistant", content: "Here's your landing page!" }],
      tool_calls: [], created_records: {}, errors: []
    }

    failed = {
      transcript: [{ role: "user", content: "Create a landing page" }],
      tool_calls: [], created_records: {}, errors: []
    }

    scorer_pass = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: passed)
    assert scorer_pass.send(:run_assertions)[:details].first[:passed]

    scorer_fail = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: failed)
    refute scorer_fail.send(:run_assertions)[:details].first[:passed]
  end

  test "Scorer check_response_contains_question" do
    scenario = build_simple_scenario(
      assertions: [{ type: :response_contains_question, on_message: 0 }]
    )

    passed = {
      transcript: [
        { role: "user", content: "Help me" },
        { role: "assistant", content: "What kind of help do you need?" }
      ],
      tool_calls: [], created_records: {}, errors: []
    }

    failed = {
      transcript: [
        { role: "user", content: "Help me" },
        { role: "assistant", content: "I created a landing page for you." }
      ],
      tool_calls: [], created_records: {}, errors: []
    }

    scorer_pass = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: passed)
    assert scorer_pass.send(:run_assertions)[:details].first[:passed]

    scorer_fail = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: failed)
    refute scorer_fail.send(:run_assertions)[:details].first[:passed]
  end

  test "Scorer distributes points evenly across assertions" do
    scenario = build_simple_scenario(
      assertions: [
        { type: :no_errors },
        { type: :conversation_completed },
        { type: :no_hallucinated_urls }
      ]
    )

    execution = {
      transcript: [{ role: "assistant", content: "Done" }],
      tool_calls: [],
      created_records: {},
      errors: []
    }

    scorer = Benchmarks::V2::Scorer.new(scenario: scenario, execution_result: execution)
    result = scorer.send(:run_assertions)

    assert result[:score] > 0
    assert result[:score] <= Benchmarks::V2::Scorer::ASSERTION_MAX
  end

  # ═══════════════════════════════════════════════════════════════
  # Scorer - Judge Response Parsing
  # ═══════════════════════════════════════════════════════════════

  test "Scorer parses valid judge JSON" do
    scenario = build_simple_scenario

    scorer = Benchmarks::V2::Scorer.new(
      scenario: scenario,
      execution_result: { transcript: [], tool_calls: [], created_records: {}, errors: [] }
    )

    json_response = '{"total_score": 35, "overall_reasoning": "Good job", "breakdown": {"task": {"score": 15, "max": 15}}, "strengths": ["fast"], "weaknesses": ["verbose"]}'

    result = scorer.send(:parse_judge_response, json_response)
    assert_equal 35, result[:score]
    assert_equal "Good job", result[:reasoning]
    assert_includes result[:strengths], "fast"
  end

  test "Scorer caps judge score at max" do
    scenario = build_simple_scenario

    scorer = Benchmarks::V2::Scorer.new(
      scenario: scenario,
      execution_result: { transcript: [], tool_calls: [], created_records: {}, errors: [] }
    )

    json_response = '{"total_score": 999, "overall_reasoning": "Perfect"}'

    result = scorer.send(:parse_judge_response, json_response)
    assert_equal Benchmarks::V2::Scorer::JUDGE_MAX, result[:score]
  end

  test "Scorer handles invalid judge JSON" do
    scenario = build_simple_scenario

    scorer = Benchmarks::V2::Scorer.new(
      scenario: scenario,
      execution_result: { transcript: [], tool_calls: [], created_records: {}, errors: [] }
    )

    result = scorer.send(:parse_judge_response, "not json at all")
    assert_equal 0, result[:score]
  end

  # ═══════════════════════════════════════════════════════════════
  # Comparator
  # ═══════════════════════════════════════════════════════════════

  test "Comparator compares scores to baseline" do
    comparator = Benchmarks::V2::Comparator.new

    run = BenchmarkRun.create!(
      entity: @entity,
      run_type: "v2_benchmark",
      benchmark_category: "v2_core",
      agent_slug: "v3_agent_loop",
      started_at: Time.current,
      completed_at: Time.current,
      total_tasks: 1,
      git_commit: "abc123"
    )

    BenchmarkTaskResult.create!(
      benchmark_run: run,
      task_id: "test_scenario",
      category: "content_creation",
      correct: true,
      metadata: { "total_score" => 75 }
    )

    report = comparator.compare(run)
    assert_not_nil report[:git_commit]
    assert_not_nil report[:scenario_comparisons]
    assert report[:scenario_comparisons].key?("test_scenario")

    run.task_results.delete_all
    BenchmarkRun.where(id: run.id).delete_all
  end

  test "Comparator detects regressions" do
    comparator = Benchmarks::V2::Comparator.new

    baseline_run = BenchmarkRun.create!(
      entity: @entity,
      run_type: "v2_benchmark",
      benchmark_category: "baseline_update",
      agent_slug: "v3_agent_loop",
      started_at: Time.current,
      completed_at: Time.current,
      total_tasks: 1,
      metadata: { "is_baseline" => "true", "baselines" => { "test_scenario" => 80 } }
    )

    current_run = BenchmarkRun.create!(
      entity: @entity,
      run_type: "v2_benchmark",
      benchmark_category: "v2_core",
      agent_slug: "v3_agent_loop",
      started_at: Time.current,
      completed_at: Time.current,
      total_tasks: 1,
      git_commit: "def456"
    )

    BenchmarkTaskResult.create!(
      benchmark_run: current_run,
      task_id: "test_scenario",
      category: "content_creation",
      correct: false,
      metadata: { "total_score" => 50 }
    )

    report = comparator.compare(current_run)
    assert_includes report[:regressions], "test_scenario"
    assert report[:scenario_comparisons]["test_scenario"][:status] == :regression

    current_run.task_results.delete_all
    BenchmarkRun.where(id: [baseline_run.id, current_run.id]).delete_all
  end

  test "Comparator detects improvements" do
    comparator = Benchmarks::V2::Comparator.new

    baseline_run = BenchmarkRun.create!(
      entity: @entity,
      run_type: "v2_benchmark",
      benchmark_category: "baseline_update",
      agent_slug: "v3_agent_loop",
      started_at: Time.current,
      completed_at: Time.current,
      total_tasks: 1,
      metadata: { "is_baseline" => "true", "baselines" => { "test_scenario" => 60 } }
    )

    current_run = BenchmarkRun.create!(
      entity: @entity,
      run_type: "v2_benchmark",
      benchmark_category: "v2_core",
      agent_slug: "v3_agent_loop",
      started_at: Time.current,
      completed_at: Time.current,
      total_tasks: 1,
      git_commit: "ghi789"
    )

    BenchmarkTaskResult.create!(
      benchmark_run: current_run,
      task_id: "test_scenario",
      category: "content_creation",
      correct: true,
      metadata: { "total_score" => 90 }
    )

    report = comparator.compare(current_run)
    assert_includes report[:improvements], "test_scenario"

    current_run.task_results.delete_all
    BenchmarkRun.where(id: [baseline_run.id, current_run.id]).delete_all
  end

  test "Comparator generates scorecard" do
    comparator = Benchmarks::V2::Comparator.new

    run = BenchmarkRun.create!(
      entity: @entity,
      run_type: "v2_benchmark",
      benchmark_category: "v2_core",
      agent_slug: "v3_agent_loop",
      started_at: Time.current,
      completed_at: Time.current,
      total_tasks: 1,
      git_commit: "jkl012"
    )

    BenchmarkTaskResult.create!(
      benchmark_run: run,
      task_id: "test_scenario",
      category: "content_creation",
      correct: true,
      metadata: { "total_score" => 75 }
    )

    report = comparator.compare(run)
    assert report[:scorecard].include?("Benchmark Scorecard")

    run.task_results.delete_all
    BenchmarkRun.where(id: run.id).delete_all
  end

  # ═══════════════════════════════════════════════════════════════
  # BenchmarkRegressionCheck
  # ═══════════════════════════════════════════════════════════════

  test "BenchmarkRegressionCheck metadata" do
    check = AmosChecks::Improvement::BenchmarkRegressionCheck
    assert_equal :benchmark_regression, check.check_name
    assert_equal :platform_improvement, check.category
    assert check.description.present?
  end

  test "BenchmarkRegressionCheck returns empty when no runs" do
    check = AmosChecks::Improvement::BenchmarkRegressionCheck.new
    findings = check.run
    assert_equal [], findings
  end

  test "BenchmarkRegressionCheck registered in AmosChecks registry" do
    registered = AmosChecks::Registry.registered_checks
    names = registered.map { |c| c[:name] }
    assert_includes names, :benchmark_regression
  end

  # ═══════════════════════════════════════════════════════════════
  # DifficultyManager
  # ═══════════════════════════════════════════════════════════════

  test "DifficultyManager reports mastered scenarios" do
    dm = Benchmarks::V2::DifficultyManager.new
    mastered = dm.mastered_scenarios
    assert mastered.is_a?(Array)
  end

  test "DifficultyManager comfort report" do
    dm = Benchmarks::V2::DifficultyManager.new
    report = dm.comfort_report

    assert report.key?(:mastered_count)
    assert report.key?(:total_scenarios)
    assert report.key?(:in_comfort_zone)
    assert report.key?(:recommendation)
  end

  test "DifficultyManager level distribution" do
    dm = Benchmarks::V2::DifficultyManager.new
    dist = dm.level_distribution

    assert dist.key?(:L2)
    assert dist[:L2].key?(:total)
    assert dist[:L2].key?(:weight)
    assert_equal 1.0, dist[:L2][:weight]
  end

  test "DifficultyManager weighted score" do
    dm = Benchmarks::V2::DifficultyManager.new

    results = [
      { scenario_id: :landing_page_multi_section, score: { total_score: 80 } },
      { scenario_id: :app_build_multi_module, score: { total_score: 60 } },
    ]

    score = dm.weighted_score(results)
    assert score > 0
  end

  # ═══════════════════════════════════════════════════════════════
  # Jobs
  # ═══════════════════════════════════════════════════════════════

  test "PostDeployBenchmarkJob is enqueueable" do
    assert_nothing_raised do
      PostDeployBenchmarkJob.new
    end
  end

  test "ContinuousBenchmarkJob is enqueueable" do
    assert_nothing_raised do
      ContinuousBenchmarkJob.new
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # ScenarioMiner
  # ═══════════════════════════════════════════════════════════════

  test "ScenarioMiner initializes with defaults" do
    miner = Benchmarks::V2::ScenarioMiner.new
    assert_not_nil miner
  end

  test "ScenarioMiner build_assertions converts text to structured assertions" do
    miner = Benchmarks::V2::ScenarioMiner.new
    assertions = miner.send(:build_assertions, [
      "Records should be created",
      "platform_create should be called",
      "No errors should occur",
      "Conversation should complete",
      "No hallucinated data"
    ])

    types = assertions.map { |a| a[:type] }
    assert_includes types, :record_exists
    assert_includes types, :tool_called
    assert_includes types, :no_errors
    assert_includes types, :conversation_completed
    assert_includes types, :no_hallucinated_data
  end

  # ═══════════════════════════════════════════════════════════════
  # Runner - Progress Callbacks & Record Detection
  # ═══════════════════════════════════════════════════════════════

  test "Runner run_suite_with_progress yields each scenario result" do
    runner = Benchmarks::V2::Runner.new(entity: @entity, user: @user)
    yielded_results = []

    # Stub the execute_scenario to avoid real LLM calls
    runner.stub(:execute_scenario, ->(scenario, benchmark_run) {
      {
        scenario_id: scenario.id,
        level: scenario.level,
        score: { total_score: 50, max_score: 100, passed: true, assertion_score: 20,
                 assertion_max: 35, judge_score: 30, judge_max: 65,
                 assertion_details: [], judge_reasoning: "Test" },
        duration_ms: 1000,
        execution_result: { transcript: [], tool_calls: [], created_records: {}, errors: [] }
      }
    }) do
      runner.run_suite_with_progress(:core) { |r| yielded_results << r }
    end

    assert yielded_results.any?, "Should yield at least one result"
    assert yielded_results.all? { |r| r[:scenario_id].present? }, "Each yielded result should have scenario_id"
    assert yielded_results.none? { |r| r.key?(:execution_result) }, "Yielded results should not include execution_result"
  end

  test "Runner detect_created_records captures status field" do
    runner = Benchmarks::V2::Runner.new(entity: @entity, user: @user)
    snapshot_time = 1.minute.ago

    contact = Contact.create!(
      entity: @entity,
      user: @user,
      first_name: "DetectTest",
      last_name: "Status",
      email: "detect_status_test_#{SecureRandom.hex(4)}@test.com",
      status: "active"
    )

    before_counts = { snapshot_at: snapshot_time }
    result = runner.send(:detect_created_records, @entity, before_counts)

    assert result["Contact"]&.any?, "Should detect the created contact"
    detected = result["Contact"].find { |r| r[:id] == contact.id }
    assert_not_nil detected, "Should find specific contact"
    assert_equal "active", detected[:status], "Should capture status field"
  ensure
    contact&.destroy
  end

  # ═══════════════════════════════════════════════════════════════
  # Scenario Cleanup Methods
  # ═══════════════════════════════════════════════════════════════

  test "ErrorRecoveryMidWorkflow cleanup removes test contacts" do
    alice = Contact.create!(
      entity: @entity, user: @user,
      first_name: "Alice", last_name: "Test",
      email: "alice@test.com"
    )
    charlie = Contact.create!(
      entity: @entity, user: @user,
      first_name: "Charlie", last_name: "Test",
      email: "charlie@test.com"
    )
    group = ContactGroup.create!(entity: @entity, user: @user, name: "Test Group")

    assert Contact.where(entity: @entity, email: "alice@test.com").exists?
    assert Contact.where(entity: @entity, email: "charlie@test.com").exists?
    assert ContactGroup.where(entity: @entity, name: "Test Group").exists?

    Benchmarks::V2::Scenarios::ErrorRecoveryMidWorkflow.cleanup!(@entity)

    refute Contact.where(entity: @entity, email: "alice@test.com").exists?,
           "alice@test.com should be cleaned up"
    refute Contact.where(entity: @entity, email: "charlie@test.com").exists?,
           "charlie@test.com should be cleaned up"
    refute ContactGroup.where(entity: @entity, name: "Test Group").exists?,
           "Test Group should be cleaned up"
  end

  test "ErrorRecoveryMidWorkflow scenario has setup proc" do
    scenario = Benchmarks::V2::ScenarioLibrary.get(:error_recovery_mid_workflow)
    assert_not_nil scenario, "error_recovery_mid_workflow should be registered"

    assert_nothing_raised do
      scenario.setup!(entity: @entity, user: @user)
    end
  end

  test "AppBuildMultiModule cleanup removes test app data" do
    assert_nothing_raised do
      Benchmarks::V2::Scenarios::AppBuildMultiModule.cleanup!(@entity)
    end
  end

  test "ContactImportAndCampaign cleanup removes test contacts" do
    assert_nothing_raised do
      Benchmarks::V2::Scenarios::ContactImportAndCampaign.cleanup!(@entity)
    end
  end

  # ═══════════════════════════════════════════════════════════════
  # Integration: All scenarios are well-formed
  # ═══════════════════════════════════════════════════════════════

  test "All registered scenarios have valid structure" do
    Benchmarks::V2::ScenarioLibrary.all.each do |scenario|
      assert scenario.id.present?, "Scenario missing id"
      assert Benchmarks::V2::Scenario::LEVELS.include?(scenario.level), "#{scenario.id}: invalid level #{scenario.level}"
      assert Benchmarks::V2::Scenario::CATEGORIES.include?(scenario.category), "#{scenario.id}: invalid category #{scenario.category}"
      assert scenario.name.present?, "#{scenario.id}: missing name"
      assert scenario.messages.any?, "#{scenario.id}: no messages"
      assert scenario.quality_rubric.present?, "#{scenario.id}: missing rubric"
      assert scenario.timeout_seconds > 0, "#{scenario.id}: invalid timeout"
    end
  end

  test "All registered scenarios have assertions" do
    Benchmarks::V2::ScenarioLibrary.all.each do |scenario|
      assert scenario.assertions.any?, "#{scenario.id}: no assertions defined"
    end
  end

  private

  def build_simple_scenario(assertions: [{ type: :no_errors }])
    Benchmarks::V2::Scenario.new(
      id: :test_scenario,
      level: :L2,
      category: :content_creation,
      name: "Test Scenario",
      description: "A test scenario",
      messages: ["Hello"],
      assertions: assertions,
      quality_rubric: "Score the response quality from 0-50."
    )
  end
end
