# frozen_string_literal: true

class AgentCapabilityRecalibrationJob < ApplicationJob
  queue_as :agents

  # Run weekly to recalibrate capability beliefs and detect specializations
  def perform
    Rails.logger.info "[AgentCapabilityRecalibrationJob] Starting weekly capability recalibration"

    stats = { agents_processed: 0, beliefs_updated: 0, specialties_found: 0, weaknesses_found: 0 }

    # Calculate population statistics for each task type
    population_stats = calculate_population_stats

    # Update each agent's capability beliefs
    AgentPlugin.available.includes(:capability_beliefs).find_each do |agent|
      begin
        agent.capability_beliefs.each do |belief|
          task_type = belief.task_type
          pop_stats = population_stats[task_type] || { mean: 0.5, std_dev: 0.1 }

          belief.recalculate_specialization!(pop_stats)

          stats[:beliefs_updated] += 1
          stats[:specialties_found] += 1 if belief.is_specialty?
          stats[:weaknesses_found] += 1 if belief.is_weakness?
        end

        # Update agent's specialties and weaknesses arrays
        update_agent_specializations(agent)

        stats[:agents_processed] += 1
      rescue => e
        Rails.logger.error "[AgentCapabilityRecalibrationJob] Error processing agent #{agent.id}: #{e.message}"
      end
    end

    Rails.logger.info "[AgentCapabilityRecalibrationJob] Completed: #{stats.to_json}"
    stats
  end

  private

  def calculate_population_stats
    stats = {}

    # Group all beliefs by task type
    AgentCapabilityBelief.where('attempts >= ?', 5).group(:task_type).each do |task_type|
      beliefs = AgentCapabilityBelief.where(task_type: task_type).where('attempts >= ?', 5)

      qualities = beliefs.pluck(:avg_quality)
      next if qualities.empty?

      mean = qualities.sum / qualities.size.to_f
      variance = qualities.map { |q| (q - mean)**2 }.sum / qualities.size.to_f
      std_dev = Math.sqrt(variance)

      stats[task_type] = { mean: mean, std_dev: [std_dev, 0.01].max }
    end

    stats
  end

  def update_agent_specializations(agent)
    specialties = agent.capability_beliefs.specialties.pluck(:task_type)
    weaknesses = agent.capability_beliefs.weaknesses.pluck(:task_type)

    # Determine primary niche
    primary = agent.capability_beliefs
      .where(is_specialty: true)
      .order(avg_quality: :desc)
      .first&.task_type

    agent.update!(
      specialties: specialties,
      weaknesses: weaknesses,
      primary_niche: primary
    )
  end
end

