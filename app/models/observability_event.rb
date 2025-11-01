# Stub model for observability tracking
# TODO: Create proper migration and implement event tracking
#
# This is a temporary stub that returns empty results for all queries
# to prevent errors while the ObservabilityEvent table doesn't exist yet.
class ObservabilityEvent
  # Mimic ActiveRecord interface without actually inheriting from it
  def self.where(*args)
    EmptyRelation.new
  end

  def self.count
    0
  end

  def self.sum(*args)
    0
  end

  def self.all
    EmptyRelation.new
  end

  def self.joins(*args)
    EmptyRelation.new
  end

  def self.includes(*args)
    EmptyRelation.new
  end

  def self.group(*args)
    EmptyRelation.new
  end

  def self.order(*args)
    EmptyRelation.new
  end

  def self.limit(n)
    EmptyRelation.new
  end

  def self.select(*args)
    EmptyRelation.new
  end

  # Empty relation that chains methods and returns empty arrays
  class EmptyRelation
    def where(*args)
      self
    end

    def not(*args)
      self
    end

    def or(*args)
      self
    end

    def includes(*args)
      self
    end

    def joins(*args)
      self
    end

    def group(*args)
      self
    end

    def order(*args)
      self
    end

    def limit(n)
      self
    end

    def select(*args)
      self
    end

    def count
      0
    end

    def sum(*args)
      0
    end

    def each
      [].each
    end

    def any?
      false
    end

    def empty?
      true
    end

    def to_a
      []
    end

    def as_json(*args)
      []
    end

    def group_by
      {}
    end

    def pluck(*args)
      []
    end
  end

  # When ready to implement, create migration:
  # rails g migration CreateObservabilityEvents event_type:string entity:references user:references metadata:jsonb
  # - event_type: string (ai_request, ai_response, tool_call, error, performance)
  # - entity_id: bigint
  # - user_id: bigint
  # - metadata: jsonb
  # - created_at: datetime
end
