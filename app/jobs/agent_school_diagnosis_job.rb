# frozen_string_literal: true

class AgentSchoolDiagnosisJob < ApplicationJob
  queue_as :default

  def perform(enrollment_id)
    enrollment = AgentSchoolEnrollment.find(enrollment_id)

    return unless enrollment.enrolled?

    school = Collaboration::AgentSchool.new
    result = school.diagnose(enrollment)

    if result[:success]
      Rails.logger.info "[AgentSchoolDiagnosisJob] Diagnosed agent #{enrollment.agent_plugin.name}"
    else
      Rails.logger.error "[AgentSchoolDiagnosisJob] Diagnosis failed: #{result[:error]}"
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[AgentSchoolDiagnosisJob] Enrollment #{enrollment_id} not found"
  end
end

