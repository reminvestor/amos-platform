# frozen_string_literal: true

class ReplacementTrainingJob < ApplicationJob
  queue_as :default

  def perform(probation_agent_id)
    agent = AgentPlugin.find(probation_agent_id)

    return unless agent.on_probation?

    Rails.logger.info "[ReplacementTrainingJob] Starting replacement training for #{agent.name}"

    # Create a new agent based on the probation agent
    replacement = create_replacement(agent)

    # Train the replacement by copying successful patterns from other agents
    train_replacement(replacement, agent)

    Rails.logger.info "[ReplacementTrainingJob] Created replacement #{replacement.name}"

    # Set up A/B test between probation agent and replacement
    setup_ab_test(agent, replacement)
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn "[ReplacementTrainingJob] Agent #{probation_agent_id} not found"
  end

  private

  def create_replacement(original)
    replacement = AgentPlugin.create!(
      name: "#{original.role.titleize} Agent (Training)",
      slug: "#{original.slug}_replacement_#{Time.current.to_i}",
      role: original.role,
      entity: original.entity,
      status: 'testing',
      description: original.description,
      system_prompt: original.system_prompt.dup,
      configuration: original.configuration.dup,
      generation: 1,
      parent_agent: original
    )

    # Create energy state
    AgentEnergyState.create!(
      agent_plugin: replacement,
      entity: replacement.entity,
      current_energy: 50
    )

    replacement
  end

  def train_replacement(replacement, original)
    # Find successful peers
    peers = AgentPlugin.active
      .where(entity: original.entity)
      .where(role: original.role)
      .where.not(id: [original.id, replacement.id])
      .joins(:energy_state)
      .where('agent_energy_states.success_rate > ?', 0.7)
      .limit(3)

    return if peers.empty?

    # Copy tools from successful peers
    peer_tools = peers.flat_map { |p| p.agent_tools.pluck(:tool_name) }.tally
    top_tools = peer_tools.sort_by { |_, count| -count }.first(5).map(&:first)

    top_tools.each do |tool_name|
      replacement.agent_tools.find_or_create_by!(tool_name: tool_name)
    end

    # Enhance prompt with successful patterns
    enhance_prompt(replacement, peers)
  end

  def enhance_prompt(replacement, peers)
    # Add guardrails based on what successful peers do
    prompt = replacement.system_prompt.dup
    prompt['learned_from_peers'] = true
    prompt['guardrails'] ||= []
    prompt['guardrails'] << "When uncertain, break tasks into smaller steps."
    prompt['guardrails'] << "Always validate outputs before completing."

    replacement.update!(system_prompt: prompt)
  end

  def setup_ab_test(probation_agent, replacement)
    AgentAbTest.create!(
      control_agent: probation_agent,
      variant_agent: replacement,
      entity: probation_agent.entity,
      status: 'running',
      target_tasks: 30,
      started_at: Time.current
    )
  end
end

