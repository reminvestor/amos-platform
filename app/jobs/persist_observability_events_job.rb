class PersistObservabilityEventsJob < ApplicationJob
  queue_as :default

  def perform(events)
    ObservabilityEvent.batch_insert(events)
  end
end
