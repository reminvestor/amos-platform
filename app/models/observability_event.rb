# Stub model for observability tracking
# TODO: Create proper migration and implement event tracking
class ObservabilityEvent < ApplicationRecord
  self.abstract_class = true

  # Stub class to prevent NameError - no database table exists yet
  # When ready to implement, remove abstract_class and create migration:
  # - event_type: string (ai_request, ai_response, tool_call, error, performance)
  # - entity_id: bigint
  # - user_id: bigint
  # - metadata: jsonb
  # - created_at: datetime

  def self.where(*args)
    none
  end

  def self.count
    0
  end

  def self.sum(*args)
    0
  end
end
