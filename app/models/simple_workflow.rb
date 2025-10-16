# Simple workflow model for the Smart Agent system
class SimpleWorkflow
  attr_accessor :name, :description, :steps, :phases, :metadata, :template_version

  def initialize(name:, description: nil, steps: [], phases: nil, metadata: {}, template_version: nil)
    @name = name
    @description = description
    @steps = steps
    @phases = phases  # V2 workflows use phases instead of steps
    @template_version = template_version
    @metadata = metadata
    @created_at = Time.current
  end

  # Check if this is a V2 workflow
  def v2?
    @template_version == 2 || @phases.present?
  end

  def to_h
    base = {
      name: @name,
      description: @description,
      metadata: @metadata,
      created_at: @created_at
    }

    # V2 workflows have phases, V1 workflows have steps
    if v2?
      base.merge(
        template_version: 2,
        phases: @phases
      )
    else
      base.merge(
        steps: @steps.respond_to?(:map) ? @steps.map(&:to_hash) : @steps
      )
    end
  end
end
