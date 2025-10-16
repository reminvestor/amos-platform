# Patch for Solid Queue to define missing JobAttributes module
#
# This solves the error: uninitialized constant SolidQueue::Execution::JobAttributes

# Only apply patch if SolidQueue is defined
if defined?(SolidQueue)
  Rails.logger.info "Applying SolidQueue::JobAttributes patch..."

  module SolidQueue
    # Define JobAttributes module if it doesn't exist
    unless defined?(JobAttributes)
      module JobAttributes
        extend ActiveSupport::Concern

        included do
          belongs_to :job, class_name: "SolidQueue::Job", optional: false
          delegate :class_name, :arguments, to: :job
        end
      end

      Rails.logger.info "SolidQueue::JobAttributes module created"
    end

    # Make sure the Execution class includes JobAttributes
    if defined?(Execution) && Execution.is_a?(Class)
      unless Execution.include?(JobAttributes)
        Execution.include(JobAttributes)
        Rails.logger.info "Applied JobAttributes to SolidQueue::Execution"
      end
    else
      Rails.logger.info "SolidQueue::Execution not loaded yet, will be patched when loaded"

      # Use ActiveSupport::Reloader to patch Execution when it's loaded
      ActiveSupport::Reloader.to_prepare do
        if defined?(SolidQueue::Execution) && SolidQueue::Execution.is_a?(Class)
          unless SolidQueue::Execution.include?(SolidQueue::JobAttributes)
            SolidQueue::Execution.include(SolidQueue::JobAttributes)
            Rails.logger.info "Applied JobAttributes to SolidQueue::Execution (deferred)"
          end
        end
      end
    end
  end
end
