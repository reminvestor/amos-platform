# Simple workflow model for the Smart Agent system
class SimpleWorkflow
  attr_accessor :name, :description, :steps, :metadata
  
  def initialize(name:, description: nil, steps: [], metadata: {})
    @name = name
    @description = description
    @steps = steps
    @metadata = metadata
    @created_at = Time.current
  end
  
  def to_h
    {
      name: @name,
      description: @description,
      steps: @steps.map(&:to_hash),
      metadata: @metadata,
      created_at: @created_at
    }
  end
end
