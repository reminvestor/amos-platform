# frozen_string_literal: true

namespace :agent_energy do
  desc "Initialize energy states for all agents"
  task init: :environment do
    puts "🔋 Initializing Agent Energy States..."

    count = 0
    errors = 0

    AgentPlugin.find_each do |agent|
      next if agent.energy_state.present?

      begin
        entity = agent.entity || Entity.first

        AgentEnergyState.create!(
          agent_plugin: agent,
          entity: entity,
          current_energy: 50.0,
          max_energy: 100.0,
          regeneration_rate: 2.0,
          last_energy_update_at: Time.current
        )

        AgentDecisionBoundary.find_or_create_by!(agent_plugin: agent)

        count += 1
        puts "  ✓ #{agent.name}"
      rescue => e
        errors += 1
        puts "  ✗ #{agent.name}: #{e.message}"
      end
    end

    # Initialize community pools
    Entity.find_each do |entity|
      CommunityEnergyPool.find_or_create_by!(entity: entity)
    end

    puts "✅ Initialized #{count} agents (#{errors} errors)"
  end

  desc "Regenerate energy for all agents"
  task regenerate: :environment do
    puts "⚡ Regenerating energy for all agents..."

    count = 0
    AgentEnergyState.find_each do |state|
      before = state.current_energy
      state.regenerate!
      after = state.current_energy

      if after != before
        puts "  #{state.agent_plugin.name}: #{before.round(1)} -> #{after.round(1)}"
        count += 1
      end
    end

    puts "✅ Regenerated #{count} agents"
  end

  desc "Distribute community pool to struggling agents"
  task distribute: :environment do
    puts "🏦 Distributing community pool..."

    CommunityEnergyPool.find_each do |pool|
      result = pool.distribute!
      if result
        puts "  Entity #{pool.entity_id}: Distributed #{result[:distributed].round(1)} to #{result[:recipients]} agents"
      else
        puts "  Entity #{pool.entity_id}: No distribution needed"
      end
    end
  end

  desc "Show energy status for all agents"
  task status: :environment do
    puts "📊 Agent Energy Status"
    puts "-" * 80

    AgentPlugin.includes(:energy_state).order(:name).each do |agent|
      state = agent.energy_state
      if state
        status = case
                 when state.in_debt? then "🔴 DEBT"
                 when state.current_energy < 20 then "🟠 LOW"
                 when state.current_energy < 50 then "🟡 MED"
                 else "🟢 OK"
                 end

        puts format("%-30s %s %6.1f / %3.0f  Success: %5.1f%%  Tasks: %d/%d",
          agent.name.truncate(30),
          status,
          state.current_energy,
          state.max_energy,
          state.success_rate * 100,
          state.tasks_completed,
          state.tasks_failed
        )
      else
        puts format("%-30s ⚪ NO STATE", agent.name.truncate(30))
      end
    end
  end

  desc "Enroll zero-energy agents in school"
  task enroll_struggling: :environment do
    puts "🎓 Enrolling struggling agents in school..."

    school = Collaboration::AgentSchool.new
    count = 0

    AgentEnergyState.where('current_energy <= 0').includes(:agent_plugin).each do |state|
      agent = state.agent_plugin
      next if agent.in_school?

      result = school.enroll(agent)
      if result[:success]
        puts "  ✓ Enrolled #{agent.name}"
        count += 1
      else
        puts "  ✗ #{agent.name}: #{result[:error]}"
      end
    end

    puts "✅ Enrolled #{count} agents"
  end

  desc "Recalibrate capability beliefs for all agents"
  task recalibrate: :environment do
    AgentCapabilityRecalibrationJob.perform_now
  end

  desc "Update decision boundaries based on recent outcomes"
  task update_boundaries: :environment do
    AgentDecisionBoundaryUpdateJob.perform_now
  end

  desc "Show collaboration statistics"
  task collab_stats: :environment do
    puts "🤝 Collaboration Statistics"
    puts "-" * 80

    total_requests = AgentCollaborationRequest.count
    completed = AgentCollaborationRequest.completed.count
    helpful = AgentCollaborationRequest.where(was_helpful: true).count

    puts "Total Requests: #{total_requests}"
    puts "Completed: #{completed}"
    puts "Helpful: #{helpful}"
    puts "Helpfulness Rate: #{total_requests > 0 ? (helpful.to_f / total_requests * 100).round(1) : 0}%"

    puts "\nBy Request Type:"
    AgentCollaborationRequest.group(:request_type).count.each do |type, count|
      puts "  #{type}: #{count}"
    end

    puts "\nTop Helpers:"
    AgentPlugin.joins(:collaboration_requests_received)
      .group('agent_plugins.id', 'agent_plugins.name')
      .order('count_all DESC')
      .limit(5)
      .count
      .each do |(_id, name), count|
        puts "  #{name}: #{count} requests handled"
      end
  end

  desc "Show school statistics"
  task school_stats: :environment do
    puts "🎓 Agent School Statistics"
    puts "-" * 80

    total = AgentSchoolEnrollment.count
    graduated = AgentSchoolEnrollment.where(outcome: 'success').count
    expelled = AgentSchoolEnrollment.where(outcome: 'failure').count
    probation = AgentSchoolEnrollment.where(outcome: 'irreplaceable_failure').count
    active = AgentSchoolEnrollment.active.count

    puts "Total Enrollments: #{total}"
    puts "Currently Active: #{active}"
    puts "Graduated: #{graduated}"
    puts "Expelled: #{expelled}"
    puts "On Probation: #{probation}"

    if total > 0
      puts "\nGraduation Rate: #{(graduated.to_f / total * 100).round(1)}%"
    end

    puts "\nAgents Currently in School:"
    AgentSchoolEnrollment.active.includes(:agent_plugin).each do |enrollment|
      puts "  #{enrollment.agent_plugin.name} - #{enrollment.status} (Attempt ##{enrollment.attempt_number})"
    end
  end
end

