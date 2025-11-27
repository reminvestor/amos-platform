# frozen_string_literal: true

class AgentSchoolEnrollmentJob < ApplicationJob
  queue_as :default

  def perform(agent_plugin_id)
    agent = AgentPlugin.find(agent_plugin_id)

    return if agent.in_school?
    return if agent.current_energy > 0

    school = Collaboration::AgentSchool.new
    result = school.enroll(agent)

    if result[:success]
      Rails.logger.info "[AgentSchoolEnrollmentJob] Enrolled agent #{agent.name}"
    else
      Rails.logger.warn "[AgentSchoolEnrollmentJob] Failed to enroll: #{result[:error]}"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[AgentSchoolEnrollmentJob] Agent #{agent_plugin_id} not found"
  end
end

