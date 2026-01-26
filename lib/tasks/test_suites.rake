# frozen_string_literal: true

# ═══════════════════════════════════════════════════════════════════════════
# Custom Test Suites
# Organize tests by category for faster feedback and targeted testing
# ═══════════════════════════════════════════════════════════════════════════

namespace :test do
  desc "Run critical path tests (experience learning, living platform, context graph)"
  task critical: :environment do
    puts "\n🎯 Running Critical Path Tests...\n\n"
    
    test_files = [
      # Experience Learning (Training-Free GRPO)
      "test/models/task_experience_test.rb",
      "test/services/learning/semantic_advantage_service_test.rb",
      "test/services/guidance_library_test.rb",
      "test/integration/experience_learning_flow_test.rb",
      
      # Living Platform
      "test/services/living_platform/evolution_cycle_service_test.rb",
      "test/services/living_platform/perception_service_test.rb",
      "test/services/living_platform/desire_engine_test.rb",
      "test/services/living_platform/lifecycle_service_test.rb",
      "test/services/living_platform/metacognition_service_test.rb",
      "test/integration/living_platform_integration_test.rb",
      
      # Context Graph
      "test/services/context_graph/decision_recorder_test.rb",
      "test/models/decision_trace_test.rb",
      
      # Core Services (Amos + Loadouts)
      "test/services/dynamic_context_service_test.rb"
    ].select { |f| File.exist?(f) }
    
    if test_files.empty?
      puts "No critical path tests found!"
      exit 1
    end
    
    puts "Tests to run: #{test_files.length}\n\n"
    
    system("bin/rails test #{test_files.join(' ')}")
    exit $?.exitstatus
  end

  desc "Run experience learning tests only"
  task experience_learning: :environment do
    puts "\n🧠 Running Experience Learning Tests...\n\n"
    
    test_files = [
      "test/models/task_experience_test.rb",
      "test/services/learning/semantic_advantage_service_test.rb", 
      "test/services/guidance_library_test.rb",
      "test/integration/experience_learning_flow_test.rb"
    ].select { |f| File.exist?(f) }
    
    system("bin/rails test #{test_files.join(' ')}")
    exit $?.exitstatus
  end

  desc "Run living platform tests only"
  task living_platform: :environment do
    puts "\n🌱 Running Living Platform Tests...\n\n"
    
    system("bin/rails test test/services/living_platform/ test/integration/living_platform_integration_test.rb")
    exit $?.exitstatus
  end

  desc "Run API controller tests"
  task api: :environment do
    puts "\n🔌 Running API Controller Tests...\n\n"
    
    system("bin/rails test test/controllers/api/")
    exit $?.exitstatus
  end

  desc "Run fast unit tests (models, services, jobs)"
  task fast: :environment do
    puts "\n⚡ Running Fast Unit Tests...\n\n"
    
    system("bin/rails test test/models/ test/services/ test/jobs/")
    exit $?.exitstatus
  end

  desc "Run pre-deploy test suite (critical + fast)"
  task pre_deploy: :environment do
    puts "\n🚀 Running Pre-Deploy Test Suite...\n\n"
    
    # Run critical first (fail fast on core functionality)
    puts "=" * 60
    puts "Step 1: Critical Path Tests"
    puts "=" * 60
    Rake::Task["test:critical"].invoke
    
    puts "\n"
    puts "=" * 60
    puts "Step 2: Fast Unit Tests"  
    puts "=" * 60
    Rake::Task["test:fast"].invoke
    
    puts "\n✅ Pre-deploy tests passed!"
  end

  desc "Run full test suite with coverage"
  task coverage: :environment do
    puts "\n📊 Running Full Test Suite with Coverage...\n\n"
    
    ENV["COVERAGE"] = "true"
    system("bin/rails test")
    
    puts "\n📈 Coverage report generated in coverage/index.html"
    exit $?.exitstatus
  end

  desc "Show test statistics"
  task stats: :environment do
    puts "\n📊 Test Statistics\n\n"
    
    test_dirs = {
      "Models" => "test/models",
      "Services" => "test/services", 
      "Controllers" => "test/controllers",
      "Integration" => "test/integration",
      "Jobs" => "test/jobs",
      "System" => "test/system",
      "Mailers" => "test/mailers"
    }
    
    total = 0
    test_dirs.each do |name, dir|
      count = Dir.glob("#{dir}/**/*_test.rb").count
      total += count
      puts "  #{name.ljust(15)} #{count.to_s.rjust(4)} tests"
    end
    
    puts "  #{'─' * 25}"
    puts "  #{'Total'.ljust(15)} #{total.to_s.rjust(4)} tests"
    puts
  end
end

# Default test task runs critical path first (only in test/dev environments)
if Rake::Task.task_defined?("test")
  Rake::Task["test"].enhance do
    puts "\n💡 Tip: Use 'bin/rails test:critical' for faster feedback on core functionality"
  end
end
