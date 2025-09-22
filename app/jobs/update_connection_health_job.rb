class UpdateConnectionHealthJob < ApplicationJob
  queue_as :default

  def perform(connection)
    # Update connection health status based on recent API call results
    connection.update_health_status!
  end
end